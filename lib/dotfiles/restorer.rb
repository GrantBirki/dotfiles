# frozen_string_literal: true

require "fileutils"
require_relative "manifest"
require_relative "runtime"

module Dotfiles
  class Restorer
    attr_reader :argv, :out, :err

    def initialize(argv:, out: $stdout, err: $stderr, state_dir: File.join(ROOT, ".dotfiles/state"))
      @argv = argv.dup
      @out = out
      @err = err
      @state_dir = state_dir
      @dry_run = false
      @state_file = nil
      @status = 0
    end

    def run
      parse_args!
      selected_state = state_file || latest_state_file
      unless selected_state && File.file?(selected_state)
        err.puts "No install state file found. Run script/install first, or pass --state PATH."
        return 1
      end

      out.puts "Using install state: #{selected_state}"
      restore_state(selected_state)
      out.puts "Restore complete." if @status.zero?
      @status
    end

    private

    attr_reader :state_file

    def dry_run?
      @dry_run
    end

    def parse_args!
      until argv.empty?
        arg = argv.shift
        case arg
        when "--dry-run", "-n"
          @dry_run = true
        when "--state"
          raise_usage!("--state requires a path", 2) if argv.empty?

          @state_file = argv.shift
        when "--production"
          next
        when "--help", "-h"
          out.print usage
          raise SystemExit, 0
        else
          raise_usage!("Unknown option: #{arg}", 2)
        end
      end
    end

    def raise_usage!(message, status)
      err.puts message
      err.print usage
      raise SystemExit, status
    end

    def usage
      <<~USAGE
        Usage: script/restore [--dry-run] [--state PATH]

        Restore files from a previous script/install state file.
      USAGE
    end

    def latest_state_file
      Dir[File.join(@state_dir, "install-*.tsv")].sort.last
    end

    def restore_state(path)
      lines = File.readlines(path, chomp: true)
      header = lines.shift.to_s.split("\t")
      lines.each do |line|
        values = line.split("\t", -1)
        row = header.zip(values).to_h
        next unless row["id"] && !row["id"].empty?

        restore_row(row)
      end
    end

    def restore_row(row)
      case row.fetch("action")
      when "linked", "copied"
        restore_changed_target(row)
      when "already-linked", "already-copied", "skipped-parent"
        out.puts "Skipping #{row.fetch("id")} (#{row.fetch("action")})."
      else
        issue "Unknown action for #{row.fetch("id")}: #{row.fetch("action")}"
      end
    end

    def restore_changed_target(row)
      backup_path = row.fetch("backup_path", "")
      if backup_path && !backup_path.empty?
        restore_from_backup(row, backup_path)
      elsif removable_managed_symlink?(row)
        remove_managed_symlink(row)
      elsif row.fetch("action") == "copied"
        out.puts "No original backup was recorded for copied target #{row.fetch("id")}; leaving #{row.fetch("target_path")} in place."
      elsif target_absent?(row.fetch("target_path"))
        out.puts "#{row.fetch("target_path")} is already absent."
      else
        issue "Refusing to remove unexpected current target for #{row.fetch("id")}: #{row.fetch("target_path")}"
      end
    end

    def restore_from_backup(row, backup_path)
      unless File.exist?(backup_path) || File.symlink?(backup_path)
        issue "Backup for #{row.fetch("id")} is missing: #{backup_path}"
        return
      end

      move_current_target_aside(row)
      if dry_run?
        out.puts "Would restore #{backup_path} to #{row.fetch("target_path")}"
      else
        FileUtils.mkdir_p(File.dirname(row.fetch("target_path")))
        FileUtils.mv(backup_path, row.fetch("target_path"))
      end
    end

    def move_current_target_aside(row)
      target_path = row.fetch("target_path")
      return if target_absent?(target_path)

      if removable_managed_symlink?(row)
        remove_managed_symlink(row)
      else
        safety_backup = Runtime.unique_path("#{target_path}.dotfiles_restore_backup")
        if dry_run?
          out.puts "Would move current #{target_path} to #{safety_backup}"
        else
          FileUtils.mv(target_path, safety_backup)
        end
      end
    end

    def removable_managed_symlink?(row)
      row.fetch("action") == "linked" &&
        File.symlink?(row.fetch("target_path")) &&
        File.readlink(row.fetch("target_path")) == row.fetch("source_path")
    end

    def remove_managed_symlink(row)
      target_path = row.fetch("target_path")
      if dry_run?
        suffix = row.fetch("backup_path", "").empty? ? " with no original backup" : ""
        out.puts "Would remove managed symlink#{suffix}: #{target_path}"
      else
        FileUtils.rm(target_path)
      end
    end

    def target_absent?(path)
      !File.exist?(path) && !File.symlink?(path)
    end

    def issue(message)
      @status = 1
      err.puts message
    end
  end
end
