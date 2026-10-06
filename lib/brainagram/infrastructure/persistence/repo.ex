defmodule Brainagram.Infrastructure.Persistence.Repo do
  use Ecto.Repo,
    otp_app: :brainagram,
    adapter: Ecto.Adapters.Postgres
end
