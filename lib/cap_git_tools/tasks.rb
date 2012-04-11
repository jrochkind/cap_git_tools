# Written using crazy meta-code cribbed from capistrano_ext so you
# can (and must) 'require' this file rather than 'load' it.
require 'capistrano'

unless Capistrano::Configuration.respond_to?(:instance)
  abort "cap_git_tools requires Capistrano 2"
end

require 'cap_git_tools/task_helpers'



Capistrano::Configuration.instance.load do  

    
  namespace :git do
    # include our helper methods, I believe just into this namespace
    # if we do it this way. 
    extend CapGitTools::TaskHelpers
    
    desc <<-DESC
      Ensure git working copy has no uncommitted changes, or abort. 
         
      If cap :branch is set, will also ensure git working copy is on same
      branch as :cap branch. 
     
      The idea is to make sure you're deploying what you're looking at.      
      See also git:guard_upstream, you often want to use both to ensure
      this. 
      
        before "git:tag", "git:check_committed", "git:check_upstream"
      or
        before "deploy",  , "git:check_committed", "git:check_upstream"
     
      setting cap :skip_guard_committed to true will skip even if task is 
      invoked. (eg, `cap deploy -s skip_guard_upstream=true`) 
    DESC
    task :guard_committed do
      if [true, "true"].include? fetch("skip_guard_committed", false)
        say_formatted("Skipping git:guard_committed")
      else  
        if exists?("branch")
          working_branch = `git symbolic-ref -q HEAD`.sub(%r{^refs/heads/}, '').chomp
          unless fetch("branch") == working_branch
            abort %Q{failed: guard_clean: wrong branch
    
        You have configured to deploy from branch ::#{fetch("branch")}::
        but your git working copy is on branch ::#{working_branch}::
    
            git checkout #{fetch("branch")}
    
        and try again. Or, to skip this check, execute cap again with:
            
            -s skip_guard_committed=true    
            }
          end
        end
        
        # cribbed from bundle release rake task
        `git diff HEAD --exit-code` 
        return_code = $?.to_i
        if return_code == 0
          say_formatted("guard_clean: passed")
        else
          abort %Q{failed: guard_clean: uncomitted changes
    
    There are files that need to be committed first.
        
    Or, to skip this check, execute cap again with:        
       -s skip_guard_committed=true  
          }
        end
      end
    end
  
    desc <<-DESC
      Ensure sure local git has been pushed to upstream, or abort
     
      * Assumes upstream remote is 'origin', or set :upstream_remote
      * Looks in :branch (default 'master') to see what branch should be checked,
        Assumes local :branch tracks upstream_remote/branch
        
      The idea is to ensure what you're deploying is what you're looking at.
      See also git:guard_committed, you usually want to use both to ensure this. 
      
        before "git:tag", "git:check_committed", "git:check_upstream"
      or if not using git:tag, eg
        before "deploy",  , "git:check_committed", "git:check_upstream"

      setting cap :skip_guard_upstream to truewill skip even if task is invoked.
      (eg, `cap deploy -s skip_guard_upstream=true`) 
    DESC
    task :guard_upstream do   
      if [true, "true"].include? fetch("skip_guard_upstream", false)
        say_formatted("Skipping git:guard_upstream")
      else      
  
        ensure_git_fetch
        
        remote_sha = `git log --pretty=format:%H #{upstream_remote}/#{working_branch} -1`.chomp
        
        unless local_sha == remote_sha
          abort %Q{failed:
    Your local #{working_branch} branch is not up to date with #{upstream_remote}/#{working_branch}.
    This will likely result in deploying something other than you expect.
    
    Please make sure you have pulled and pushed all code before deploying:
    
        git pull #{upstream_remote} #{working_branch}
        # run tests, etc
        git push #{upstream_remote} #{working_branch}
    
    Or, to skip this check run cap again with `-s skip_guard_upstream=true`
          }
        end
        
        say_formatted("guard_upstream: passed")
      end
    end
    
    desc <<-DESC
      Tags the current checkout and pushes tag to remote.
      
      Normally will tag and deploy whatever is in your current git working
      copy -- you may want to use with the guard tasks to make sure
      you're deploying what you think and sync'ing it to your upstream
      repository:
      
        before "deploy", "git:guard_committed", "git:guard_upstream", "git:tag"
        
      However, if you have set cap :branch, git:retag will tag the HEAD
      of THAT branch, rather than whatever is the current working copy
      branch. 
      
      Either way, git:tag:
      * pushes the new tag to upstream remote git
      * sets the cap :branch variable to the newly created tag, to be 
        sure cap deploys that tag. 
      
      What will the created tag look like?
      
      Without multi-stage, by default something like `deploy-yyyy-mm-dd-hhmm`. 
      
      * The deploy- prefix will be the current stage name if multi-stage.
      * The prefix can be manually set in config file or command line
        with cap :tag_prefix variable instead.
      * Somewhat experimental, you can also set :tag_format to change the
        part after the prefix.
    DESC
    task :tag do    
      
      # make sure we have any other deployment tags that have been pushed by
      # others so our auto-increment code doesn't create conflicting tags
      ensure_git_fetch
  
      tag = calculate_new_tag
      
      commit_msg = @__git_what || "cap git:tag: #{tag}"
      
      # tag 'working_branch', means :branch if set, otherwise
      # current working directory checkout. 
      local_sh "git tag -a -m '#{commit_msg}' #{tag} #{self.working_branch}"
  
      # Push new tag back to origin
      local_sh "git push -q #{upstream_remote} #{tag}"
      
      # set :branch to tag, so cap will continue on to deploy the tag we just created!    
      set(:branch, tag)
    end
    
    desc <<-DESC
      Takes an already existing tag, and retags it and deploys that tag.
    
        Will push the new tag to upstream repo, and set the new tag as cap 
        :branch so cap willd deploy it.  
    
        Usually used in git multistage for moving from staging to production, 
        for instance in your production.rb:
        
          before "deploy", "git:retag" 
        
        Or use with the guard tasks:
          before "deploy", "git:guard_committed", "git:guard_upstream", "git:retag"
        
        `set :confirm_retag, true` in the config file to force an interactive
        prompt and confirmation before continuing. 
        
        What tag will be used as source tag?
        
        * Normally the most recent tag beginning "staging-"
        * Or set cap :tag_prefix in config file or command line
          to use a different prefix.
        * Or set :tag_from in config file or on command line
          to specify a specific tag.
          
        What will the newly created tag look like? Same rules as for
        git:tag. 
        
        * By default in a production stage it's going to look 
        like `production-yyyy-mm-dd-hhmm`, but there are several
        of cap variables you can set in a config file to change this,
        including :tag_prefix and :tag_format.         
    DESC
    task :retag do
      from_tag = self.from_tag
      
      to_tag = calculate_new_tag
      
      self.guard_confirm_retag(from_tag)
      
      say_formatted("git:retag taking #{from_tag} and retagging as #{to_tag}")
      
      local_sh "git tag -a -m 'tagging #{from_tag} for deployment as #{to_tag}' #{to_tag} #{from_tag}"
      
      # Push new tag back to origin
      local_sh "git push -q #{upstream_remote} #{to_tag}"
        
      set(:branch, to_tag)
    end
    
    desc <<-DESC
      Show 5 most recent tags set by git:tag or git:retag
      
      Can be used to see what you've deployed recently. 
      
         cap git:show_tags
       or for multi-stage:
         cap staging git:show_tags
         cap production git:show_tags
      
      Looks for tags matching the prefix that the tag or retag task
      would use to tag. Ie, 'deploy-', or 'stagename-' in multi-stage,
      or according to :tag_prefix setting. 
     
      Will also output date of tag, commit message, and account doing the commit.            
    DESC
    task :show_tags do               
      # in newer versions of git you could prob do this with a git-log instead with
      # certain arguments, but my local git is too old to support --tags arg properly.
      system "git for-each-ref --count=4 --sort='-taggerdate' --format='\n* %(refname:short)\n    Tagger: %(taggeremail)\n    Date: %(taggerdate)\n\n    %(subject)' 'refs/tags/#{tag_prefix}-*' "
    end
    
  
    desc <<-DESC
     Show log between most tagged deploy and what would be deployed now.                
     
     Requires you to be using git:tag or git:retag to make any sense,
     so we can find the 'last deployed' tag to compare. 
     
     You can run this manually:
         cap git:commit_log
     Or for multi-stage, perhaps:
         cap staging git:commit_log
         cap production git:commit_log
     Or you can use cap callbacks to ensure this is shown before
     a deploy, for multi-stage for instance add to your production.rb:
        before "git:retag", "git:commit_log"
        # and force an interactive confirmation after they've seen it
        set :confirm_retag, true     
     
     Ordinarily shows commit log between current git working copy
     (forced to current head of :branch if cap :branch is set), and
     last deployed tag, by default tag beginning "deploy-", or
     tag beginning :stage if you are cap multi-stage, or beginning
     with :tag_prefix if that is set. 
          
     Hard-coded to do something special if you are using multistage
     cap, and are in stage 'production' -- in that case it will
     show you the commits between the most recent production-* tag,
     and the most recent staging-* tag. (Cap :tag_prefix and :from_prefix
     can change those tag prefixes).      
    DESC
    task :commit_log do
      from, to = nil, nil
      
      if exists?("stage") && stage.to_s == "production"
        # production stage in multi-stage
        from =  from_tag # last staging-* tag, or last :from_prefix tag
        to = fetch_last_tag # last deploy-* tag, or last :tag_prefix tag
      else
        # 'staging' stage in multi-stage, or else any old
        # non-multistage. 
        from = fetch_last_tag # last deploy-* tag, or last :tag_prefix tag
        to = local_sha.slice(0,8) # current git working copy, or local branch head. 
      end
      
      show_commit_log(from, to)
    end
    
    
    
  end
  
  
end