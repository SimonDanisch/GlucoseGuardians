using HTTP

const GIT_PATH = Ref{Union{Nothing, String}}(nothing)

function git_cmd(command)
    if isnothing(GIT_PATH[])
        system_git_path = Sys.which("git")
        if isnothing(system_git_path)
            error("Unable to find `git`; Please install it: https://git-scm.com/book/en/v2/Getting-Started-Installing-Git")
        end
        GIT_PATH[] = system_git_path
    end
    return `$(GIT_PATH[]) $command`
end

function git(command)
    try
        run(git_cmd(command))
        return nothing
    catch e
        @error "Git failed to run command: $(command)" exception = (e, catch_backtrace())
        return e
    end
end

"""
    gitrm_copy(src, dst)

Uses `git rm -r` to remove `dst` and then copies `src` to `dst`. Assumes that the working
directory is within the git repository of `dst` is when the function is called.

This is to get around [#507](https://github.com/JuliaDocs/Documenter.jl/issues/507) on
filesystems that are case-insensitive (e.g. on OS X, Windows). Without doing a `git rm`
first, `git add -A` will not detect case changes in filenames.
"""
function copy_files(src, dst)
    # Copy individual entries rather then the full folder since with
    # versions=nothing it would replace the root including e.g. the .git folder
    for x in readdir(src)
        cp(joinpath(src, x), joinpath(dst, x); force=true)
    end
end

# Generate a closure with common commands for ssh and https
function deploy_with_git(repository_dir, website_dir, upstream, branch)
    cd(repository_dir) do
        # Setup git.
        git(`init`)
        git(`config user.name "Deploy"`)
        git(`config user.email "website@github.com"`)

        # Fetch from remote and checkout the branch.
        git(`remote add upstream $upstream`)
        git(`fetch upstream`)
        err = git(`checkout -b $branch upstream/$branch`)
        if err !== nothing
            @warn "checking out $branch failed with error: $err"
            git(`checkout --orphan $branch`)
            git(`commit --allow-empty -m "Initial empty commit for docs"`)
        end

        copy_files(website_dir, repository_dir, force=true)

        # Add, commit, and push the docs to the remote.
        git(`add -A .`)
        if !success(git_cmd(`diff --cached --exit-code`))
            git(`commit -m "doc Deploy"`)
            git(`push -q upstream HEAD:$branch`)
        else
            @warn "new docs identical to the old -- not committing nor pushing."
        end
    end
end


cfg = (repository="SimonDanisch/GlucoseGuardians", owner="SimonDanisch", name="GlucoseGuardians")

function authenticated_repo_url(cfg)
    actor = get(ENV, "GITHUB_ACTOR", "octocat")
    return "https://$(actor):$(ENV["GITHUB_TOKEN"])@github.com/$(cfg.repository).git"
end

upstream = authenticated_repo_url(cfg)

empty_repo = normpath(joinpath(@__DIR__, "..", "..", "Test"))
rm(empty_repo; recursive=true, force=true)
mkdir(empty_repo)
deploy_with_git(empty_repo, website_dir, upstream, "gh-pages")

function post_github_status(; type::String, owner::String, repo::String, sha::String, subfolder=nothing)
    try
        ## Need an access token for this
        auth = get(ENV, "GITHUB_TOKEN", nothing)
        auth === nothing && return
        # construct the curl call
        headers = ["Authorization" => "token $(auth)"
            "User-Agent" => "Documenter.jl",
            "Content-Type" => "application/json",
        ]

        json = Dict{String,Any}("context" => "documenter/deploy", "state" => type)
        if type == "pending"
            json["description"] = "Documentation build in progress"
        elseif type == "success"
            json["description"] = "Documentation build succeeded"
            target_url = "https://$(owner).github.io/$(repo)/"
            if subfolder !== nothing
                target_url *= "$(subfolder)/"
            end
            json["target_url"] = target_url
        elseif type == "error"
            json["description"] = "Documentation build errored"
        elseif type == "failure"
            json["description"] = "Documentation build failed"
        else
            error("unsupported type: $type")
        end
        body = sprint(JSON.print, json)
        url = "https://api.github.com/repos/$(owner)/$(repo)/statuses/$(sha)"
        result = HTTP.post(url, headers, body)
    catch e
        @debug "Failed to post status" exception = (e, catch_backtrace())
    end
    return nothing
end

function post_status(; type, repo::String, subfolder=nothing, kwargs...)
    try # make this non-fatal and silent
        # If we got this far it usually means everything is in
        # order so no need to check everything again.
        # In particular this is only called after we have
        # determined to deploy.
        sha = nothing
        if get(ENV, "GITHUB_EVENT_NAME", nothing) == "pull_request"
            event_path = get(ENV, "GITHUB_EVENT_PATH", nothing)
            event_path === nothing && return
            event = JSON.parsefile(event_path)
            if haskey(event, "pull_request") &&
               haskey(event["pull_request"], "head") &&
               haskey(event["pull_request"]["head"], "sha")
                sha = event["pull_request"]["head"]["sha"]
            end
        elseif get(ENV, "GITHUB_EVENT_NAME", nothing) == "push"
            sha = get(ENV, "GITHUB_SHA", nothing)
        end
        sha === nothing && return
        return post_github_status(type, repo, sha, subfolder)
    catch
        @debug "Failed to post status"
    end
end


function push_build(;
        site_root, subfolder, repo,
        branch="gh-pages"
    )

    # upstream is used by the closures above, kind of hard to track
    upstream = authenticated_repo_url(repo)
    try
        cd(() -> git_commands(upstream, branch)), site_root)
        post_status(repo=repo, type="success", subfolder=subfolder)
    catch e
        @error "Failed to push:" exception = (e, catch_backtrace())
        post_status(repo=repo, type="error")
        rethrow(e)
    end
end

"""
    create_clean_gh_pages(repository_folder, branch="gh-pages")

Creates a clean, empty branch that isn't connected to the repositories history.
This is perfect for the gh-pages branch from which we deploy the website
"""
function create_clean_gh_pages(repository_folder, branch="gh-pages")
    cd(repository_folder) do
        git(`symbolic-ref HEAD refs/heads/$(branch)`)
        rm(".git/index")
        git(`clean -fdx`)
        # we need something to commit!
        open("index.html", "w") do io
            write(io, "Hello world")
        end
        git(`add .`)
        git(`commit -a -m "First pages commit"`)
        git(`push origin $(branch)`)
    end
end
