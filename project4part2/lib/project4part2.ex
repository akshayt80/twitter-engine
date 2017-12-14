defmodule Project4part2 do
    @moduledoc """
    Project4part2 keeps the contexts that define your domain
    and business logic.

    Contexts are also responsible for managing your data, regardless
    if it comes from the database, an external API or others.
    """
    use Application
    require Logger
    def start(_type, _args) do
        Logger.info "Inside start"
        import Supervisor.Spec

        # Define workers and child supervisors to be supervised
        children = [
          # Start the endpoint when the application starts
          supervisor(Project4part2Web.Endpoint, []),
          # Start your own worker by calling: Twitter.Worker.start_link(arg1, arg2, arg3)
          # worker(Twitter.Worker, [arg1, arg2, arg3]),
        ]
        init()
        #spawn fn -> stats_print() end
        # See https://hexdocs.pm/elixir/Supervisor.html
        # for other strategies and supported options
        opts = [strategy: :one_for_one, name: Project4part2.Supervisor]
        Supervisor.start_link(children, opts)
    end
    defp init() do
        Logger.info "initialize all the required tables"
        Logger.debug "creating tables"
        Logger.debug "creating hashtags table"
        :ets.new(:hashtags, [:set, :public, :named_table, read_concurrency: true])
        Logger.debug "creating mentions table"
        :ets.new(:mentions, [:set, :public, :named_table, read_concurrency: true])
        Logger.debug "creating users table"
        # {username, status, subscribers, feed, port}
        :ets.new(:users, [:set, :public, :named_table, read_concurrency: true])
        Logger.debug "creating counter record"
        :ets.new(:counter, [:set, :public, :named_table, read_concurrency: true])
        :ets.insert(:counter, {"tweets", 0})
        :ets.insert(:counter, {"total_users", 0})
        :ets.insert(:counter, {"online_users", 0})
        :ets.insert(:counter, {"offline_users", 0})
    end
    defp stats_print(period \\ 10000, last_tweet_count \\ 0) do
        :timer.sleep period
        current_tweet_count = :ets.lookup_element(:counter, "tweets", 2)
        tweet_per_sec = (current_tweet_count - last_tweet_count) / (10000 / 1000)
        total_users = :ets.lookup_element(:counter, "total_users", 2)
        online_users = :ets.lookup_element(:counter, "online_users", 2)
        offline_users = :ets.lookup_element(:counter, "offline_users", 2)
        Logger.info "Server Stats\nTweets(per sec): #{tweet_per_sec}\nTotal Users: #{total_users}\nOnline Users: #{online_users}\nOffline Users: #{offline_users}"
        stats_print(period, current_tweet_count)
    end
end
