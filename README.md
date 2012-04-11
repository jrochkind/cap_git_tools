# cap_git_tools

Re-usable, composable [Capistrano](https://github.com/capistrano/capistrano) tasks for git tagging and other work with the
git repository you use for your Cap deploys. 

* Ensure your local git is committed and pushed, so you are deploying what you
think you are. 
* Automatically git tag the deploy
* Enforce a [multistage](https://github.com/capistrano/capistrano/wiki/2.x-Multistage-Extension) workflow where only a tagged staging release can be deployed
to production (ala [gitflow](https://github.com/apinstein/git-deployment))

Functionality is split into discrete yet composable tasks, with sensible defaults 
but configurable, so you can build a cap recipe that fits *your*
requirements and workflow. Ordinary single stage or multi-stage; with or without
interactive confirmation prompts; using git however you're already or would like
to be using it. 

(_Inspired by Alan Pinstein and Josh Nichols' neat
[gitflow](https://github.com/apinstein/git-deployment), but refactored for more
flexiblity with less hardcoded workflow. Some functionality changed in the
process.)_

## Installation

    gem install cap_git_tools
    
Or if in the context of something using bundler such as Rails, add to Gemfile
eg:

    gem 'cap_git_tools', :group => :development
    
Add to top of a relevant Capistrano file (such as config/deploy.rb ordinarily):

    require 'cap_git_tools/tasks'
    
This makes cap_git_tool's tasks available to you, but doesn't automatically wire
them up to be used by your `cap deploy`. See below. 

## Ensure git is committed and pushed when deploying

Have you ever deployed the 'wrong' thing, because you forgot to commit and/or
push your changes to git?  I have. 

Have cap make sure you're committed and pushed before deploying by adding to
your recipe in deploy.rb: 

    before "deploy", "git:guard_committed", "git:guard_pushed"
    
Or use just one or the other -- guard_committed makes sure you have no
uncommitted changes, and makes sure your current working copy branch matches
the branch Cap is using (if any).   guard_pushed makes sure the current working
copy branch (or local branch matching Cap :branch, if set) matches the upstream
remote version. 
 
## Automatically tag on deploy

Every time you deploy, want to have Capistrano automatically tag exactly what
gets deployed, with a tag like "deploy-2012-04-11-1517"?  

Add this to your Cap recipe, usefully combining with the tasks to make sure
your git copy is 'clean' as discussed above:

    before "deploy", "git:guard_committed", "git:guard_pushed", "git:tag"
   
That's a date and timestamp, deploy-yyyy-mm-dd-hhmm.

If you are using multistage, the default prefix will be the current stage name
like "production" or "staging" (but see below for fancier multi-stage
workflow). 

You can customize the prefix and other aspects of tagging, both in your recipe 
and with command line over-rides, see `cap -E git:tag` for more info. 

## Multistage workflow

Are you using Capistrano's [multistage
extension](https://github.com/capistrano/capistrano/wiki/2.x-Multistage-Extension)? 
In one commonly desired multistage workflow (similar to what
[gitflow](https://github.com/apinstein/git-deployment) enforces):
 
 * Under staging, you want automatic tagging with staging-yyyy-mm-dd-hhmm, just 
   as above under 'Automatically tag on deploy'. Add to your config/staging.rb:
   
      before "deploy", "git:guard_committed", "git:guard_pushed", "git:tag"
      
 * Under production, you want to take the most recent 'staging' tag, and promote
   it by deploying that tag to production, re-tagging with a "production-" tag.
   Maybe you also want to print out the commit log between the last production
   tag and what you're about to deploy, and require interactive confirmation.
   Add to your config/deploy.rb:
   
       before "deploy",  "git:commit_log", "git:retag"
       set :confirm_tag, true
       
Say you `cap staging deploy` on April 1 2012 at noon, your deploy will be
tagged `staging-2012-04-01-1200`. Say on April 2 at noon, you run `cap
production deploy` -- you'll be a shown a commit log of changes between the
previous `production-` commit and your most recent `staging-` commit, 
`staging-2012-04-01-1200`. You'll be asked to confirm, and then the deploy will
happen, with new tag added `production-2012-04-02-1200` Note it's timestamped
with date of production deploy).  The commit message for the `production-` tag
will say which `staging-` tag was retagged. 
     
The `git:retag` task has some configurable options (in your recipe or on the
individual command line invocation) too, see `cap -e git:retag`. 
 
## Make your own recipe

Look at `cap -T git` to see the tasks added by cap_git_tools. Run `cap -e
taskname` to see expanded documentation info on each one, covering more 
specifics of what it does and what cap variables can alter it's behavior. 

Some behaviors can be customized by 'capistrano variables'. These can be set in
a recipe:

    set :variable, "value"
   
Or set/over-ridden on the individual cap command line invocation:

   cap deploy -s variable=value
   
Doesn't matter if you use cap '-s' or '-S', cap_git_tools tasks always lazily
look up these values. 

## Other tools

`cap git:commit_log` to see the commits between the *last* tagged release
and what you'd deploy now with `cap deploy`. Works in singlestage recipe, or
multistage under 'cap staging git:commit_log' or 'cap production
git:commit_log'. 

`cap git:show_tags` to show the last 3 deploy tags, with meta information.
Works in single stage recipe or multistage. 

## To Be Done

Tag names are automatically created with a year-month-day-hour-minute timestamp.
However, if you try to deploy again before the minute's changed on the clock,
the tasks will try to re-tag using an already used name. You'll get an error and
the task will abort, but the task could be written to catch this and add a
suffix. But it ain't yet. 

There is some limited experimental functionality to change the format and add
new components to the automatically created tag name, using a :tag_format
variable. This theoretically allows the `who` and `what` components used by
gitflow.  But doing the 'right thing' in multistage (copying the 'what' from the
previous tag, but regenerating the rest) is a bit tricky, and hasn't been done
yet, which is what keeps this functionality limited and experimental at this
point. 

## Let me know

Feedback, pull requests, complaints, welcome. Not sure if anyone's gonna use
this. 