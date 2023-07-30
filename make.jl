using Revise, JSServe, Website

routes, task, server = interactive_server(Website.asset_paths()) do
    return Routes(
        "/" => App(index_page, title="Home"),
    )
end


false && deploy_website(routes)
