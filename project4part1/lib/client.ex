defmodule Client do
    use GenServer
    require Logger
    def start_link(server_ip, port, mode \\ :interactive) do
        # Connect to server
        Logger.debug "Establishing Server connection"
        {:ok, socket} = :gen_tcp.connect(server_ip, port, [:binary, {:active, false},{:packet, 0}])
        Logger.debug "Server Connection Established"
        username = IO.gets "Enter username: "
        username = String.trim(username)
        perform_registration(socket, username)
        #spawn fn -> start_communication(socket, self())end
        # create clients and assign neigbors to them
        # TODO:- before first step we must register the user at server
        GenServer.start_link(__MODULE__, %{'tweets'=> [], 'subscribers'=> MapSet.new}, name: :myClient)
        #start_communication(socket, self())
        # TODO:- remove hardcoded username
        spawn fn -> listen(socket, username) end
        if mode == :interactive do
            interactive_client(socket, username)
        end
    end
    defp interactive_client(socket, username) do
        option = IO.gets "Options:\n1. Tweet\n2. Hashtag query\n3. Mention query\n4. Subscribe\n5. unsubscribe\n6. Login\n7. Logout\nEnter your choice: "
        case String.trim(option) do
            # "1" -> username = IO.gets "Enter username: "
            #         username = String.trim(username)
            #         perform_registration(socket, username)
            "1" -> tweet = IO.gets "Enter tweet: "
                    send_tweet(socket, String.trim(tweet), username)
            "2" -> hashtag = IO.gets "Enter hashtag to query for: "
                    hashtag_query(socket, String.trim(hashtag), username)
            "3" -> mention = IO.gets "Enter the username(add @ in begining) to look for: "
                    mention_query(socket, String.trim(mention), username)
            "4" -> user = IO.gets "Enter the username you want to follow: "
                    subscribe(socket, String.split(user, [" ", "\n"], trim: true), username)
            "5" -> user = IO.gets "Enter the username you want to unsubscribe: "
                    unsubscribe(socket, String.split(user, [" ", "\n"], trim: true), username)
            "6" -> perform_login(socket, username)
            "7" -> perform_logout(socket, username)
            _ -> IO.puts "Invalid option. Please try again"
        end
        interactive_client(socket, username)
    end
    #TODO:- write a function which creates simulation for client
    # defp start_communication(socket, parent) do
    #     Logger.debug "sending Hello"
    #     raw_data = %{"function" => :register, "reply"=> true, "data"=> %{}}
    #     data = Poison.encode!(raw_data)
    #     socket |> :gen_tcp.send(data)
    #     # Receive k value from server
    #     {:ok, data} = :gen_tcp.recv(socket, 0)
    #     Logger.debug "received message from server: #{data}"
    # end

    def init(map) do
        {:ok, map}
    end

    def send_message(receiver, data) do
        encoded_response = Poison.encode!(data)
        :gen_tcp.send(receiver, encoded_response)
    end

    def receive_message(receiver) do
        # TODO:- do thorough testing of this function as it sometimes causes error
        {:ok, data} = :gen_tcp.recv(receiver, 0)
        Logger.debug "Received message: #{data}"
        Poison.decode!(data)
    end

    defp blocking_send_message(receiver, data) do
        send_message(receiver, data)
        receive_message(receiver)
    end

    defp create_message_map(action, data) do
        %{"function" => action, "data"=> data}
    end

    def handle_cast({:register, username, server}, map) do
        data = %{"username"=> username}
        send_message(server, create_message_map(:register, data))
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
        Logger.info "username:#{username} sender: #{sender} incoming tweet:- #{tweet}"
        # with probability od 10% do retweet
        if :rand.uniform(100) <= 10 do
            Logger.debug "username:#{username} doing retweet"
            data = %{"function"=> "tweet", "username"=> username, "tweet"=> tweet}
            send_message(socket, data)
        end
        {:noreply, map}
    end

    def handle_cast({:feed, feed}, map) do
        Logger.debug "Incoming feed which was accumulated while you were offline"
        for item <- feed do
            Logger.info "Tweet: #{item}"
        end
        {:noreply, map}
    end

    ####################

    def listen(socket, username) do
        {:ok, data} = :gen_tcp.recv(socket, 0)
        data = Poison.decode!(data)
        Logger.debug "received data at user #{username} data: #{inspect(data)}"

        # Send value of k as String
        #Logger.debug "sending initial message"
        #:gen_tcp.send(worker, "Welcome to the Twitter")
        #GenServer.cast(:myClient, {:initial, data, worker})
        case data["function"] do
           "hashtag" -> GenServer.cast(:myClient, {:hashtag, data["tweets"]})
           "mention" -> GenServer.cast(:myClient, {:mention, data["tweets"]})
           "tweet" -> GenServer.cast(:myClient, {:tweet, username, data["sender"], data["tweet"], socket})
           "feed" -> GenServer.cast(:myClient, {:feed, data["feed"]})
        end
        listen(socket, username)
    end

    def perform_logout(server, username, autologin \\ false) do
        # send logout message
        data = %{"function"=> "logout", "username"=> username}
        send_message(server, data)
        # sleep for some random time between 1 to 10 sec
        if autologin do
            sec = :rand.uniform(10) * 1000
            Logger.debug "#{username} sleeping for #{sec} seconds"
            :timer.sleep sec
            # send login back to server
            perform_login(server, username)
        end
        #response = blocking_send_message(server, data)
        #Logger.info "Tweets while you were offline: #{inspect(response["tweets"])}"
        # print the feed
        # TODO:- get the feed
    end

    defp perform_login(server, username) do
        data = %{"function"=> "login", "username"=> username}
        Logger.debug "Sending login message to server"
        send_message(server, data)
    end

    def perform_registration(server, username \\ "akshayt80") do
        # send register message to server
        data = %{"function"=> "register", "username"=> username}
        data = blocking_send_message(server, data)
        if data["status"] != "success" do
            Logger.debug "No success while registering"
            #perform_registration(server, generate_random_str())
        else
            # send login message to server
            send_message(server, %{"function"=> "login", "username"=> username})

            # send subscriber message to server
            users = data["users"]
            Logger.info "Current users at server: #{inspect(users)}"
            # take user input for subscribing to some users or pick some random users to subscribe
            #input = IO.gets "Enter user to subscribe to space separated? "
            #friends = input |> String.split([" ", "\n"], trim: true)
            #friend = String.trim(input, "\n")
            #data = %{"function"=> "subscribe", "username"=> username, "users"=> friends}
            #send_message(server, data)
        end
    end

    # defp perform_first_login(server, users) do
    #     # randomly pick some user to subscribe to
    # end

    def received_tweet(server, username, tweet) do
        # print tweet
        Logger.info "username:#{username} incoming tweet:- #{tweet}"
        # with probability od 10% do retweet
        if :rand.uniform(100) <= 10 do
            Logger.debug "username:#{username} doing retweet"
            data = %{"function"=> "tweet", "username"=> username, "tweet"=> tweet}
            send_message(server, data)
        end
    end

    def process_feed(feed) do
        Logger.debug "Incoming feed"
        for item <- feed do
            Logger.info "Tweet: #{item}"
        end
    end

    # defp query_server(server, username, key) do
    #     # no need to do this in simulator
    #     # send message to server to get mentions
    #     data = %{'function'=> 'mention', 'name'=> username}
    #     send_message(server, data)
    #     # print all the tweets with mention
    #     # TODO:- server is not sending back the tweets from feed
    #     # send message to server to get hashtags
    #     data = %{'function'=> 'hashtags', 'hashtag'=> username}
    #     send_message(server, data)
    #     # print all the tweets with hashtag
    # end

    defp send_tweet(socket, tweet, username) do
        data = %{"function"=> "tweet", "username"=> username, "tweet"=> tweet}
        send_message(socket, data)
    end

    defp hashtag_query(socket, hashtag, username) do
        data = %{"function"=> "hashtag", "username"=> username, "hashtag"=> hashtag}
        send_message(socket, data)
    end

    defp mention_query(socket, mention, username) do
        data = %{"function"=> "mention", "mention"=> mention, "username"=> username}
        send_message(socket, data)
    end

    defp subscribe(socket, users, username) do
        data = %{"function"=> "subscribe", "users"=> users, "username"=> username}
        send_message(socket, data)
    end

    defp unsubscribe(socket, users, username) do
        data = %{"function"=> "unsubscribe", "users"=> users, "username"=> username}
        send_message(socket, data)
    end

    #############################
    # Client utility functions
    #############################

    defp generate_random_str(len \\ 9) do
        common_str = "abcdefghijklmnopqrstuvwxyz0123456789"
        list = common_str |> String.split("", trim: true) |> Enum.shuffle
        random_str = 1..len |> Enum.reduce([], fn(_, acc) -> [Enum.random(list) | acc] end) |> Enum.join("")
        random_str
    end
end
