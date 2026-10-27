defmodule BrainagramWeb.Router do
  use BrainagramWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {BrainagramWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug BrainagramWeb.Locale
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # O player embutido em outros sites: sem sessão, sem cookie, sem LiveView,
  # com cabeçalhos próprios que liberam só esta rota para iframes.
  pipeline :embed do
    plug :accepts, ["html"]
    plug BrainagramWeb.EmbedHeaders
  end

  scope "/embed", BrainagramWeb do
    pipe_through :embed

    get "/:slug", EmbedController, :show
  end

  scope "/", BrainagramWeb do
    pipe_through :browser

    live_session :default, on_mount: BrainagramWeb.Locale do
      live "/", DashboardLive, :index
      live "/new", EditorLive, :new
      live "/d/:slug", EditorLive, :show
    end

    get "/d/:slug/preview.svg", PreviewController, :show
    get "/d/:slug/download", ExportController, :diagram
    get "/export", ExportController, :bundle
  end

  # Other scopes may use custom stacks.
  # scope "/api", BrainagramWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:brainagram, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: BrainagramWeb.Telemetry
    end
  end
end
