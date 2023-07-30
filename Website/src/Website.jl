module Website

using JSServe

asset_path(files...) = joinpath(@__DIR__, "assets", files...)
asset_paths(files...) = [asset_path(files...)]

asset(files...) = Asset(asset_path(files...))

function parse_markdown(session, file)
    source = read(file, String)
    return JSServe.string_to_markdown(session, source)
end

function page(session, file)
    dom = parse_markdown(session, file)
    return DOM.html(
        DOM.head(
            DOM.meta(charset="UTF-8"),
            DOM.meta(name="viewport", content="width=device-width, initial-scale=1"),
            asset("site.css"),
            # DOM.link(rel="icon", type="image/x-icon", href=asset("images", "favicon.ico")),
        ),
        DOM.body(dom)
    )
end

function index_page(session::Session)
    page(session, joinpath(@__DIR__, "markdown/index.md"))
end

export index_page

end # module Website
