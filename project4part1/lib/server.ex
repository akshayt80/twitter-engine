defmodule Server do
    use GenServer
    require Logger

    def start_link(port) do
        Logger.debug "occupying the socket"
        # create clients and assign neigbors to them
        {:ok, listen_socket} = :gen_tcp.listen(port,[:binary,
                                                    {:ip, {0,0,0,0}},
                                                    {:packet, 0},
                                                    {:active, false},
                                                    {:reuseaddr, true}])
        Logger.debug "socket connection established"
        #spawn fn -> loop_acceptor(listen_socket, self()) end
        GenServer.start_link(__MODULE__, %{'hashtags'=> %{}, 'mentions'=> %{}, 'online'=> MapSet.new, 'offline'=> MapSet.new, 'registeredUsers'=> MapSet.new}, name: :myServer)
        loop_acceptor(listen_socket, self())
    end

    defp loop_acceptor(socket, parent) do
        Logger.debug "Ready to accept new connections"
        {:ok, worker} = :gen_tcp.accept(socket)
        
        # Spawn receive message in separate process
        spawn fn -> serve(worker, parent) end
        # Loop to accept new connection
        loop_acceptor(socket, parent)
    end

    defp serve(worker, parent) do
        {:ok, data} = :gen_tcp.recv(worker, 0)
        data = Poison.decode!(data)
        Logger.debug "received data from worker #{inspect(worker)} data: #{inspect(data)}"

        # Send value of k as String
        Logger.debug "sending initial message"
        #:gen_tcp.send(worker, "Welcome to the Twitter")
        GenServer.cast(:myServer, {:initial, data, worker})
        case Map.get(data, "function") do
           "register" -> GenServer.cast(:myServer, {:register, Map.get(data, "username"), worker})
           "login" -> GenServer.cast(:myServer, {:login, Map.get(data, "username"), worker})
           "logout" -> GenServer.cast(:myServer, {:logout, Map.get(data, "username"), worker}) 
           "hashtag" -> GenServer.cast(:myServer, {:hashtag, Map.get(data, "hashtag"), worker})
           "mention" -> GenServer.cast(:myServer, {:mention, Map.get(data, "mention"), worker})
           "tweet" -> GenServer.cast(:myServer, {:tweet, Map.get(data, "username"), Map.get(data, "tweet")})
           "subscribe" -> GenServer.cast()
           "unsubscribe" -> GenServer.cast()
        end
        serve(worker, parent)
    end

    defp send_response(client, data) do
        encoded_response = Poison.encode!(data)
        :gen_tcp(worker, encoded_response)
    end

    def init(map) do
        {:ok, map}
    end

    def handle_cast({:initial, data, client}, map) do
        Logger.debug "Inside handle_call"
        :gen_tcp.send(client, "Welcome to the Twitter")
        {:noreply, map}
    end

    def handle_cast({:register, username, client}, map) do
        # if username unique then send ok
        # else send :error
        # TODO:- registeredUser set becomes redundant as we have userid in main map
        if username in map["registeredUsers"] do
            #{:reply, {:error, "already exists"}, map}
            send_response(client, %{"status"=> "error", "message"=> "Username already exists"})
        else
            registeredUsers = MapSet.put(map["registeredUsers"], username)
            map = Map.put(map, username, %{"subscribers"=> MapSet.new, "feed"=> :queue.new})
            map = Map.put(map, "registeredUsers", registeredUsers)
            send_response(client, %{"status"=> "success", "message"=> "Added new user"})
            #{:reply, {:ok, "success"}, Map.put(map, "registeredUsers", registeredUsers)}
        end
        {:noreply, map}
    end

    def handle_cast({:login, username, client}, map) do
        online_set = map['online']
        offline_set = map['offline']
        if MapSet.member?(offline_set, username) do
            offline_set = MapSet.delete(offline_set, username)
            # TODO:- send the messages accumulated at the server asyncly while the client was offline
        end
        online_set = MapSet.put(online_set, username)
        temp_dict = %{'online' => online_set, 'offline' => offline_set}
        map = Map.merge(map, temp_dict) 
        #{:reply, {:ok, "success"}, map}
        {:noreply, map}
    end

    def handle_cast({:logout, username}, map) do
        online_set = map['online']
        offline_set = map['offline']
        if MapSet.member?(online_set, username) do
            online_set = MapSet.delete(online_set, username)
        end
        offline_set = MapSet.put(offline_set, username)
        temp_dict = %{'online' => online_set, 'offline' => offline_set}
        map = Map.merge(map, temp_dict) 
        #{:reply, {:ok, "success"}, map}
        {:noreply, map}
    end

    def handle_cast({:hashtag, hashtag, client}, map) do
        hashtags = map["hashtags"]
        if Map.has_key? hashtags, hashtag do
            # TODO:- see how to send a list as bytes in elixir
            #{:reply, {:hashtag, Map.get(hashtags, hashtag)}, map}
            {:noreply, map}

        else
            #{:reply, {:nohashtag, "None"}, map}
            {:noreply, map}

        end
    end

    def handle_cast({:mention, name, client}, map) do
        mentions = map["mentions"]
        if Map.has_key? mentions, name do
            # TODO:- see how to send a list as bytes in elixir
            #{:reply, {:mention, Map.get(mentions, name)}, map}
            {:noreply, map}
        else
            #{:reply, {:nomention, "None"}, map}
            {:noreply, map}
        end
    end

    def handle_cast({:tweet, username, tweet}, map) do
        hashTagMap = Map.get map, 'hashtags'
        mentionMap = Map.get map, 'mentions'
        components = SocialParser.extract(tweet,[:hashtags,:mention])
        if Map.has_key? components, :hashtags do
            hashTagValues = Map.get(components, :hashtags)
            hashTagMap = loop(hashTagValues, List.last(hashTagValues), hashTagMap, tweet)
            map = Map.put map, 'hashtags', hashTagMap
        end

        if Map.has_key? components, :mention do
            mentionValues = Map.get(components, :mention)
            mentionMap = loop(mentionValues, List.last(mentionValues), mentionMap, tweet)
            map = Map.put map, 'mentions', mentionMap
        end
        {:noreply, map}
    end

    def handle_cast({:subscribe, username, subscribing}, map) do
        {:noreply, map}
    end

    def handle_cast({:unsubscribe, username, unsubscribe}map) do
        {:noreply, map}
    end

    ##########################
    # Server Utility functions
    ##########################

    defp add_in_set(set, value) do
        MapSet.put set, value
    end

    defp enqueue(queue, value) do
        if :queue.member value, queue do
            queue
        else
            :queue.in queue, value
        end
    end

    defp dequeue(queue) do
        {element, queue} = :queue.out queue
        if element == :empty do
            {:empty, queue}
        else
            value = elem(element, 1)
            {value, queue}
        end
    end

    defp peek(queue) do
        result = :queue.peek queue
        if is_tuple result do
            elem(result, 1)
        else
            result
        end
    end

    defp loop(list, last, map, tweet, current) when last == current do
        map
    end

    defp loop(list, last, map, tweet, current \\ None) do
        [current| list] = list
        set = Map.get(map, current) |> MapSet.put(tweet)
        map = Map.put map, current, set
        loop(list, last, map, current)
    end
end
