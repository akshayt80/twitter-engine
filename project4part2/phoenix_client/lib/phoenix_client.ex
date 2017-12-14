defmodule PhoenixClient do

  require Logger

  def main(args) do
    {_, args, _} = OptionParser.parse(args)
    server_ip = Enum.at(args, 0)
    port = 4000
    start_link(server_ip, port, :interactive)
  end

  def start_link(server_ip, port, mode \\ :interactive, username \\ None, users \\ None, frequency \\ :medium) do
        # Connect to server
        Logger.debug "Establishing Server connection"
        {:ok, pid} = PhoenixChannelClient.start_link()

        Logger.debug "Server Connection Established"
        if mode == :interactive do
            username = IO.gets "Enter username: "
            username = String.trim(username)
        else
            Logger.debug "username given #{username} with frequency:#{frequency}"
        end

        timeline_channel = channel_connect(pid, username, server_ip)
        GenServer.start_link(__MODULE__, %{"mode"=> mode, "retweet_prob"=> 10, "status"=> :online}, name: :"#{username}")

        if mode == :interactive do
            spawn_pid = spawn fn -> interactive_client(timeline_channel, username) end
        end
        listen(username, timeline_channel, spawn_pid, pid, server_ip)
    end

    defp channel_connect(pid, username, server_ip \\ "127.0.0.1") do

      socket = case PhoenixChannelClient.connect(pid,
          host: server_ip,
          port: 4000,
          path: "/socket/websocket",
          params: %{token: "something", username: username},
          secure: false) do
         {:ok, socket} -> socket
         {:error, error_info} -> Logger.error "User already exists"
            Process.exit(self(), :kill)
        end

      timeline_channel = PhoenixChannelClient.channel(socket, "timeline:feed", %{username: username})
      
      case PhoenixChannelClient.join(timeline_channel) do
        {:ok, %{}} -> :ok
        {:error, %{reason: reason}} -> IO.puts(reason)
        :timeout -> IO.puts("timeout")
      end

      timeline_channel

    end

    defp interactive_client(timeline_channel, username) do
        option = IO.gets "Options:\n1. Tweet\n2. Hashtag query\n3. Mention query\n4. Subscribe\n5. Unsubscribe\n6. Login\n7. Logout\nEnter your choice: "
        case String.trim(option) do
            "1" -> tweet = IO.gets "Enter tweet: "
                  tweet = String.trim(tweet)
                  send_tweet(timeline_channel, tweet, username)
            "2" -> hashtag = IO.gets "Enter hashtag(add # in begining) to query for: "
                    hashtag_query(timeline_channel, String.trim(hashtag), username)
            "3" -> mention = IO.gets "Enter the username(add @ in begining) to look for: "
                    mention_query(timeline_channel, String.trim(mention), username)
            "4" -> user = IO.gets "Enter the username you want to follow: "
                    subscribe(timeline_channel, String.split(user, [" ", "\n"], trim: true), username)
            "5" -> user = IO.gets "Enter the username you want to unsubscribe: "
                    # TODO:- complete the logic for unsubscribe. maybe use map of user and channel object
                    unsubscribe(timeline_channel, String.split(user, [" ", "\n"], trim: true), username)
            "6" -> perform_login(timeline_channel, username)
            "7" -> perform_logout(timeline_channel, username)
            _ -> IO.puts "Invalid option. Please try again"
        end
        interactive_client(timeline_channel, username)
    end
    def init(map) do
        {:ok, map}
    end
    def handle_cast({:register, data}, map) do
        if data["status"] != "success" do
            Logger.debug "No success while registering"
        else
            users = data["users"]
            Logger.info "Current users at server: #{inspect(users)}"
        end
        {:noreply, map}
    end

    def handle_cast({:mention, tweets}, map) do
        for tweet <- tweets do
            Logger.info "Tweet: #{tweet}"
        end
        {:noreply, map}
    end

    def handle_cast({:hashtag, tweets}, map) do
        for tweet <- tweets do
            Logger.info "Tweet: #{tweet}"
        end
        {:noreply, map}
    end

    def handle_cast({:tweet, username, sender, tweet, socket}, map) do
        if map["status"] == :online do
          Logger.info "username:#{username} sender: #{sender} incoming tweet:- #{tweet}"
          mode = map["mode"]
          if mode == :interactive do
              input = IO.gets "Want to retweet(y/n)? "
              input = String.trim(input)
              if input == "y" do
                  Logger.debug "username:#{username} doing retweet"
                  data = %{"function"=> "tweet", "username"=> username, "tweet"=> tweet}
                  send_message(socket, "tweet", data)
              end
          end
        end
        {:noreply, map}
    end

    def handle_cast({:feed, feed}, map) do
        Logger.debug "Incoming feed which was accumulated while you were offline"
        feed_tweets = Enum.join(feed, "\n")
        Logger.info "Tweets: #{feed_tweets}"
        {:noreply, map}
    end

    def handle_cast({:login}, map) do
      map = Map.put(map, "status", :online)
      {:noreply, map}
    end

    def handle_cast({:logout}, map) do
      map = Map.put(map, "status", :offline)
      {:noreply, map}
    end

    def listen(username, timeline_channel, spawn_pid, pid, server_ip) do
        receive do
          {"tweet", data} ->
            if Enum.member?(data["followers"], username) or Enum.member?(data["mentions"], username) do
              GenServer.cast(:"#{username}", {:tweet, username, data["username"], data["tweet"], timeline_channel})
            end
          :close -> Process.exit(spawn_pid, :kill)
            timeline_channel = channel_connect(pid, username, server_ip)
            spawn_pid = spawn fn -> interactive_client(timeline_channel, username) end
          {:error, error} -> ()
        after
          5000 -> 
        end
        listen(username, timeline_channel, spawn_pid, pid, server_ip)
    end
    defp send_tweet(tweetChannel, tweet, username) do
        data = %{"function"=> "tweet", "username"=> username, "tweet"=> tweet}
        send_message(tweetChannel, "tweet", data)
    end

    defp hashtag_query(socket, hashtag, username) do
        data = %{"function"=> "hashtag", "username"=> username, "hashtag"=> hashtag}
        send_recv_message(socket, "hashtag", data)
    end

    defp mention_query(socket, mention, username) do
        data = %{"function"=> "mention", "mention"=> mention, "username"=> username}
        send_recv_message(socket, "mention", data)
    end

    defp subscribe(socket, users, username) do
        for user <- users do
          data = %{function: "subscribe", user: user, username: username}
          send_message(socket, "subscribe", data)
        end
    end
    defp unsubscribe(socket, users, username) do
        for user <- users do
            data = %{"function"=> "unsubscribe", "user"=> user, "username"=> username}
            send_message(socket, "unsubscribe", data)
        end
    end
    def perform_logout(server, username) do
        # send logout message
        data = %{"function"=> "logout", "username"=> username}
        GenServer.cast(:"#{username}", {:logout})
        send_message(server, "logout", data)
    end

    defp perform_login(server, username) do
        data = %{"function"=> "login", "username"=> username}
        Logger.debug "Sending login message to server"
        send_recv_message(server, "login", data)
        GenServer.cast(:"#{username}", {:login})
    end
    def perform_registration(server, username \\ "akshayt80") do
        data = %{"function"=> "register", "username"=> username}
        send_message(server, "register", data)
    end
    defp send_message(channel, type, message) do
      case PhoenixChannelClient.push(channel, type, message) do
        :ok -> IO.puts("successfully sent message")
        {:error, %{reason: reason}} -> IO.puts(reason)
        :timeout -> IO.puts("timeout")
      end
    end
    defp send_recv_message(channel, type, message) do
      case PhoenixChannelClient.push_and_receive(channel, type, message, 100) do
        {:ok, data} -> function = data["function"]
                        username = data["username"]
                        GenServer.cast(:"#{username}", {:"#{function}", data["tweets"]})
        {:error, %{reason: reason}} -> IO.puts(reason)
        :timeout -> IO.puts("timeout")
      end
    end
end
