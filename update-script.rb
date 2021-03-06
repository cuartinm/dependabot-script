# This script is designed to loop through all dependencies in a GHE, GitLab or
# Azure DevOps project, creating PRs where necessary.

require "dependabot/file_fetchers"
require "dependabot/file_parsers"
require "dependabot/update_checkers"
require "dependabot/file_updaters"
require "dependabot/pull_request_creator"
require "dependabot/omnibus"
require "gitlab"
require 'octokit'

package_manager_hash = {
  "Ruby" => "bundler",
  "Python" => "pip (includes pipenv)",
  "HTML" => "npm_and_yarn",
  "TypeScript" => "npm_and_yarn",
  "JavaScript" => "npm_and_yarn",
  "Java" => "gradle",
  "Go" => "go_modules",
  "Docker" => "docker",
}

credentials = [
  {
    "type" => "git_source",
    "host" => "github.com",
    "username" => "x-access-token",
    "password" => ENV["GITHUB_ACCESS_TOKEN"] # A GitHub access token with read access to public repos
  }
]

client = Octokit::Client.new(:access_token => ENV["GITHUB_ACCESS_TOKEN"])
repositories = client.repos({}, query: {type: 'owner', sort: 'created'})

repositories.each do |repo|

  repo_name = repo.full_name
  directory = "/"
  package_manager = package_manager_hash[repo.language]

  unless package_manager.nil?

    source = Dependabot::Source.new(
      provider: "github",
      repo: repo_name,
      directory: directory,
      branch: nil,
    )

    # Fetch the dependency files #
    puts "Fetching #{package_manager} dependency files for #{repo_name}"
    fetcher = Dependabot::FileFetchers.for_package_manager(package_manager).new(
      source: source,
      credentials: credentials,
    )
    files = fetcher.files
    commit = fetcher.commit

    # Parse the dependency files #
    puts "Parsing dependencies information"
    parser = Dependabot::FileParsers.for_package_manager(package_manager).new(
      dependency_files: files,
      source: source,
      credentials: credentials,
    )

    dependencies = parser.parse

    dependencies.select(&:top_level?).each do |dep|
      # Get update details for the dependency #
      checker = Dependabot::UpdateCheckers.for_package_manager(package_manager).new(
        dependency: dep,
        dependency_files: files,
        credentials: credentials,
      )
    
      next if checker.up_to_date?
    
      requirements_to_unlock =
        if !checker.requirements_unlocked_or_can_be?
          if checker.can_update?(requirements_to_unlock: :none) then :none
          else :update_not_possible
          end
        elsif checker.can_update?(requirements_to_unlock: :own) then :own
        elsif checker.can_update?(requirements_to_unlock: :all) then :all
        else :update_not_possible
        end
    
      next if requirements_to_unlock == :update_not_possible
    
      updated_deps = checker.updated_dependencies(
        requirements_to_unlock: requirements_to_unlock
      )
    
      # Generate updated dependency files #
      print "  - Updating #{dep.name} (from #{dep.version})…"
      updater = Dependabot::FileUpdaters.for_package_manager(package_manager).new(
        dependencies: updated_deps,
        dependency_files: files,
        credentials: credentials,
      )
    
      updated_files = updater.updated_dependency_files
    
      # Create a pull request for the update #
      pr_creator = Dependabot::PullRequestCreator.new(
        source: source,
        base_commit: commit,
        dependencies: updated_deps,
        files: updated_files,
        credentials: credentials,
        assignees: [(ENV["PULL_REQUESTS_ASSIGNEE"] || ENV["GITLAB_ASSIGNEE_ID"])&.to_i],
        label_language: true,
        author_details: {
          email: "dependabot@YOUR_DOMAIN",
          name: "dependabot"
        },
      )
      pull_request = pr_creator.create
      puts " submitted"
    
      next unless pull_request
    end
  end

end

puts "Done"
