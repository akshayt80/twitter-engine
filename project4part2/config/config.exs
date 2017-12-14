# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# Configures the endpoint
config :project4part2, Project4part2Web.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "RlAOl3pytyGLYVK9MEW/pUFuIkdKfJCr3hLw5Q2AnH/7Q+lRbni+Gv0lnF318XI4",
  render_errors: [view: Project4part2Web.ErrorView, accepts: ~w(html json)],
  pubsub: [name: Project4part2.PubSub,
           adapter: Phoenix.PubSub.PG2]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env}.exs"
