module RubyInstaller
module Build # Use for: Build, Runtime
module Components
class PacmanUpdate < Base
  def self.depends
    %w[msys2]
  end

  def description
    "MSYS2 repository update"
  end

  def execute(args)
    msys = BuildOrRuntime.msys2_installation
    msys.with_msys_apps_enabled do
      puts "#{description} ..."
      res = run_verbose("pacman", "-Sy", "--needed", "--noconfirm")
      puts "#{description} #{res ? green("succeeded") : red("failed")}"
      raise "pacman failed" unless res
    end
  end
end
end
end
end
