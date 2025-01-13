class ResourcesResolver
  def self.get_resource_url(resource)
    base_url = "https://raw.githubusercontent.com"
    repo   = ENV["HOMEBREW_EMACS_HEAD_GITHUB_REPOSITORY"]
    branch = ENV["HOMEBREW_EMACS_HEAD_GITHUB_REPOSITORY_REF"]
    local_resources  = ENV["HOMEBREW_USE_LOCAL_RESOURCES"]

    if repo
      if branch
        [base_url, repo, branch.sub("refs/heads/", ""), resource].join("/")
      else
        [base_url, repo, "main", resource].join("/")
      end
    else
      if local_resources
        "file:///" + Dir.pwd + "/" + resource
      else
        [base_url, "neoheartbeats", "homebrew-emacsthenno", "main", resource].join("/")
      end
    end
  end
end
