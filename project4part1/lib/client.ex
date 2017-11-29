defmodule Client do
    use GenServer
    require Logger
    def simulate(server_ip, port, user_count \\ 3) do
        user_set = 1..user_count |> Enum.reduce(MapSet.new, fn(x, acc) -> MapSet.put(acc, "user_#{x}") end)
        constant = zipf_constant(user_count)
        Logger.debug "zipf constant: #{constant}"
        # Top 10%  and bootom 10% of total
        high = low = round(:math.ceil(user_count * 0.1))
        for n <- 1..user_count do
            username = "user_#{n}"
            available_subscribers = MapSet.difference(user_set, MapSet.new([username]))
            subscriber_count = zipf_prob(constant, n, user_count)
            Logger.debug "user: user_#{n} subscriber_count: #{subscriber_count}"
            subscribers = get_subscribers(available_subscribers, subscriber_count)
            frequency = :medium
            if n <= high do
                frequency = :high
            end
            if n >= low do
              frequency = :low
            end
            spawn fn -> start_link(server_ip, port, :simulate, username, subscribers, frequency) end
        end
        keep_alive()
    end
    def keep_alive() do
        :timer.sleep 10000
        keep_alive()
    end
    # number represents number of user which is used in username in simulation mmode
    # users is list of all available users
    # frequency if :high then every 200 ms one tweet will be sent, :medium every 700ms and :slow every 1200ms
    def start_link(server_ip, port, mode \\ :interactive, username \\ None, users \\ None, frequency \\ :medium) do
        # Connect to server
        Logger.debug "Establishing Server connection"
        {:ok, socket} = :gen_tcp.connect(server_ip, port, [:binary, {:active, false},{:packet, 0}])
        Logger.debug "Server Connection Established"
        if mode == :interactive do
            username = IO.gets "Enter username: "
            username = String.trim(username)
        else
            #username = "user_#{number}"
            Logger.debug "username given #{username} with frequency:#{frequency}"
        end
        perform_registration(socket, username)

        if mode == :simulate do
            #:timer.sleep 1000
            # subscribe to users
            Logger.debug "performing bulk_subscription for user: #{username} followers: #{inspect(users)}"
            bulk_subscription(socket, users, username)
        end

        GenServer.start_link(__MODULE__, %{"mode"=> mode, "retweet_prob"=> 10}, name: :"#{username}")
        spawn fn -> listen(socket, username) end
        if mode == :interactive do
            interactive_client(socket, username)
        else
            simulative_client(socket, username, frequency)
        end
    end

    defp simulative_client(socket, username, frequency) do
        #send tweet
        tweet = generate_random_str(100)
        Logger.debug "#{username} sending tweet: #{tweet}"
        send_tweet(socket, tweet, username)
        #sleep
        # perform logout
        if frequency == :high do
            :timer.sleep(200)
            simulate_logout(socket, username, frequency)
        else
            if frequency == :medium do
                :timer.sleep(700)
                simulate_logout(socket, username, frequency)
            else
                :timer.sleep(1200)
                simulate_logout(socket, username, frequency)
            end
        end
        simulative_client(socket, username, frequency)
    end

    defp get_subscribers(available_subscribers, subscriber_count) do
        Enum.shuffle(available_subscribers) |> Enum.take(subscriber_count) |> MapSet.new()
    end

    defp simulate_logout(socket, username, frequency) do
        random_num = :rand.uniform(100)
        if frequency == :high and random_num <= 3 do
            # autologin is turned true
            perform_logout(socket, username, true)
        else
            if frequency == :medium and random_num <= 5 do
                # autologin is turned true
                perform_logout(socket, username, true)
            else
                if random_num <= 7 do
                    # autologin is turned true
                    perform_logout(socket, username, true)
                end
            end
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
        mode = map["mode"]
        if mode != :interactive and :rand.uniform(100) <= map["retweet_prob"] do
            Logger.debug "username:#{username} doing retweet"
            data = %{"function"=> "tweet", "username"=> username, "tweet"=> tweet}
            send_message(socket, data)
        end
        if mode == :interactive do
            input = IO.gets "Want to retweet(y/n)? "
            input = String.trim(input)
            if input == "y" do
                Logger.debug "username:#{username} doing retweet"
                data = %{"function"=> "tweet", "username"=> username, "tweet"=> tweet}
                send_message(socket, data)
            end
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
        {status, response} = :gen_tcp.recv(socket, 0)
        if status == :ok do
            # this will handle the case when there are more than one
            multiple_data = response |> String.split("}", trim: :true)
            for data <- multiple_data do
                Logger.debug "data to be decoded: #{inspect(data)}"
                data = Poison.decode!("#{data}}")
                Logger.debug "received data at user #{username} data: #{inspect(data)}"

                # Send value of k as String
                #Logger.debug "sending initial message"
                #:gen_tcp.send(worker, "Welcome to the Twitter")
                #GenServer.cast(:myClient, {:initial, data, worker})
                case data["function"] do
                   "hashtag" -> GenServer.cast(:"#{username}", {:hashtag, data["tweets"]})
                   "mention" -> GenServer.cast(:"#{username}", {:mention, data["tweets"]})
                   "tweet" -> GenServer.cast(:"#{username}", {:tweet, username, data["sender"], data["tweet"], socket})
                   "feed" -> GenServer.cast(:"#{username}", {:feed, data["feed"]})
                end
            end
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
           # send_message(server, %{"function"=> "login", "username"=> username})

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

    defp bulk_subscription(socket, users, username) do
        data = %{"function"=> "bulk_subscription", "users"=> users, "username"=> username}
        send_message(socket, data)
    end

    defp unsubscribe(socket, users, username) do
        data = %{"function"=> "unsubscribe", "users"=> users, "username"=> username}
        send_message(socket, data)
    end

    #############################
    # Client utility functions
    #############################

    defp generate_random_str(len) do
        common_str = "  abcdefghijklmnopqrstuvwxyz  0123456789"
        list = common_str |> String.split("", trim: true) |> Enum.shuffle
        random_str = 1..len |> Enum.reduce([], fn(_, acc) -> [Enum.random(list) | acc] end) |> Enum.join("")
        random_str
    end

    defp zipf_constant(users) do

        # c = (Sum(1/i))^-1 where i = 1,2,3....n
        users = for n <- 1..users, do: 1/n
        :math.pow(Enum.sum(users), -1)
    end
    defp zipf_prob(constant, user, users) do
        # z=c/x where x = 1,2,3...n
        round((constant/user)*users)
    end
end
