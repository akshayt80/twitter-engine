defmodule Client do
    use GenServer
    require Logger
    def start_link(server_ip, port) do
        # Connect to server
        Logger.debug "Establishing Server connection"
        {:ok, socket} = :gen_tcp.connect(server_ip, port, [:binary, {:active, false},{:packet, 0}])
        Logger.debug "Server Connection Established"
        #spawn fn -> start_communication(socket, self())end
        # create clients and assign neigbors to them
        # TODO:- before first step we must register the user at server
        GenServer.start_link(__MODULE__, %{'tweets'=> [], 'subscribers'=> MapSet.new}, name: :myClient)
        #start_communication(socket, self())
        # TODO:- remove hardcoded username
        spawn fn -> listen(socket, "akshayt80") end
    end
    #TODO:- write a function which creates simulation for client
    defp start_communication(socket, parent) do
        Logger.debug "sending Hello"
        raw_data = %{"function" => :register, "reply"=> true, "data"=> %{}}
        data = Poison.encode!(raw_data)
        socket |> :gen_tcp.send(data)
        # Receive k value from server
        {:ok, data} = :gen_tcp.recv(socket, 0)
        Logger.debug "received message from server: #{data}"
    end

    def init(map) do
        {:ok, map}
    end

    def send_message(receiver, data) do
        encoded_response = Poison.encode!(data)
        :gen_tcp.send(receiver, encoded_response)
    end

    def receive_message(receiver) do
        {:ok, data} = :gen_tcp.recv(receiver, 0)
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

    def handle_cast({:login, }, map) do
       {:noreply, map} 
    end

    def handle_cast({:logout}, map) do
        {:noreply, map}
    end

    def handle_cast({:mention}, map) do
        {:noreply, map}
    end

    def handle_cast({:hashtag}, map) do
        {:noreply, map}
    end

    def handle_cast({:tweet, username, sender, tweet, socket}, map) do
        Logger.debug "user: #{username} sender: #{sender} tweet: #{tweet}"
        received_tweet(socket, username, tweet)
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
        case Map.get(data, "function") do
           "hashtag" -> GenServer.cast(:myClient, {:hashtag, Map.get(data, "hashtag"), socket})
           "mention" -> GenServer.cast(:myClient, {:mention, Map.get(data, "mention"), socket})
           "tweet" -> GenServer.cast(:myClient, {:tweet, username, Map.get(data, "sender"), Map.get(data, "tweet"), socket})
           "subscribe" -> GenServer.cast(:myClient, {:subscribe, data["username"], data["users"]})
           "unsubscribe" -> GenServer.cast(:myClient, {:unsubscribe, data["username"], data["users"]})
           "feed" -> spawn fn -> process_feed(data["feed"]) end
        end
        listen(socket, username)
    end

    def perform_logout(server, username) do
        # send logout message
        data = %{'function'=> 'logout', 'username'=> username}
        send_message(server, data)
        # sleep for some random time between 1 to 10 sec
        sec = :rand.uniform(10) * 1000
        Logger.debug "#{username} sleeping for #{sec}"
        :timer.sleep sec
        # send login back to server
        data = %{'function'=> 'login', 'username'=> username}
        send_message(server, data)
        # print the feed
        # TODO:- get the feed
    end

    def perform_registration(server, username \\ "akshayt80") do
        # send register message to server
        data = %{"function"=> "register", "username"=> username}
        data = blocking_send_message(server, data)
        if Map.get(data, "status") != "success" do
            Logger.debug "No success while registering"
            #perform_registration(server, generate_random_str())
        else
            # send login message to server
            data = %{"function"=> "login", "username"=> username}
            # expects servers response to proceed
            send_message(server, data)

            # send subscriber message to server
            users = data["users"]
            Logger.info "Current users: #{inspect(users)}"
            # take user input for subscribing to some users or pick some random users to subscribe
            input = IO.gets "Enter user to subscribe to space separated? "
            friends = input |> String.split([" ", "\n"], trim: true)
            #friend = String.trim(input, "\n")
            data = %{"function"=> "subscribe", "username"=> username, "users"=> friends}
            send_message(server, data)
        end
    end

    defp perform_first_login(server, users) do
        # randomly pick some user to subscribe to
    end

    def received_tweet(server, username, tweet) do
        # print tweet
        Logger.info "username:#{username} incoming tweet:- #{tweet}"
        # with probability od 10% do retweet
        if :rand.uniform(100) <= 10 do
            Logger.debug "username:#{username} doing retweet"
            data = %{'function'=> 'tweet', 'username'=> username, 'tweet'=> tweet}
            send_message(server, data)
        end
    end

    def process_feed(feed) do
        Logger.debug "Incoming feed"
        for item <- feed do
            Logger.info "Tweet: #{item}"
        end
    end

    defp query_server(server, username, key) do
        # no need to do this in simulator
        # send message to server to get mentions
        data = %{'function'=> 'mention', 'name'=> username}
        send_message(server, data)
        # print all the tweets with mention
        # TODO:- server is not sending back the tweets from feed
        # send message to server to get hashtags
        data = %{'function'=> 'hashtags', 'hashtag'=> username}
        send_message(server, data)
        # print all the tweets with hashtag
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
