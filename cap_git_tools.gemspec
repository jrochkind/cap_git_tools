# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "cap_git_tools/version"

Gem::Specification.new do |s|
  s.name        = "cap_git_tools"
  s.version     = CapGitTools::VERSION
  s.authors     = ["Jonathan Rochkind"]
  s.email       = ["jonathan@dnil.net"]
  s.homepage    = "http://github.com/jrochkind/cap_git_tools"
  s.summary     = %q{re-usable, composable Capistrano tasks for git tagging and other work with a git repo}

  s.rubyforge_project = "cap_git_tools"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]


  s.add_dependency "capistrano", "~> 2.0"
end
