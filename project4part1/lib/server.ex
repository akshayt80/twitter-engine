defmodule Server do
    use GenServer

    def start_link() do
        # create clients and assign neigbors to them
        GenServer.start_link(__MODULE__, %{'hashtags'=> %{}, 'mentions'=> %{}, 'online'=> MapSet.new, 'offline'=> MapSet.new, 'registeredUsers'=> MapSet.new}, [])
    end

    def init(map) do
        {:ok, map}
    end

    def handle_call({:register, username}, _from, map) do
        # if username unique then send ok
        # else send :error
        # TODO:- registeredUser set becomes redundant as we have userid in main map
        if username in map["registeredUsers"] do
            {:reply, {:error, "already exists"}, map}
        else
            registeredUsers = MapSet.put(map["registeredUsers"], username)
            map = Map.put(map, username, %{"subscribers"=> MapSet.new, "feed"=> :queue.new})
            {:reply, {:ok, "success"}, Map.put(map, "registeredUsers", registeredUsers)}
        end
    end

    def handle_call({:login, username}, _from, map) do
        online_set = map['online']
        offline_set = map['offline']
        if MapSet.member?(offline_set, username) do
            offline_set = MapSet.delete(offline_set, username)
            # TODO:- send the messages accumulated at the server asyncly while the client was offline
        end
        online_set = MapSet.put(online_set, username)
        temp_dict = %{'online' => online_set, 'offline' => offline_set}
        map = Map.merge(map, temp_dict) 
        {:reply, {:ok, "success"}, map}
    end

    def handle_call({:logout, username}, _from, map) do
        online_set = map['online']
        offline_set = map['offline']
        if MapSet.member?(online_set, username) do
            online_set = MapSet.delete(online_set, username)
        end
        offline_set = MapSet.put(offline_set, username)
        temp_dict = %{'online' => online_set, 'offline' => offline_set}
        map = Map.merge(map, temp_dict) 
        {:reply, {:ok, "success"}, map}
    end

    def handle_cast({:hashtag, hashtag}, _from, map) do
        hashtags = map["hashtags"]
        if Map.has_keys? hashtags, hashtag do
            # TODO:- see how to send a list as bytes in elixir
            {:reply, {:hashtag, Map.get(hashtags, hashtag)}, map}
        else
            {:reply, {:nohashtag, "None"}, map}
        end
    end

    def handle_cast({:mention, name}, _from, map) do
        mentions = map["mentions"]
        if Map.has_keys? mentions, name do
            # TODO:- see how to send a list as bytes in elixir
            {:reply, {:mention, Map.get(mentions, name)}, map}
        else
            {:reply, {:nomention, "None"}, map}
        end
    end

    def handle_cast({:tweet, {username, message}}, _from, map) do
        hashTagMap = Map.get map, 'hashtags'
        mentionMap = Map.get map, 'mentions'
        components = SocialParser.extract(message,[:hashtags,:mention])
        if Map.has_key? components, :hashtags do
            hashTagValues = Map.get(components, :hashtags)
            hashTagMap = loop(hashTagValues, List.last hashTagValues, hashTagMap, :tweet)
            map = Map.put map, 'hashtags', hashTagMap
        end

        if Map.has_key? components, :mention do
            mentionValues = Map.get(components, :mention)
            mentionMap = loop(mentionValues, List.last mentionValues, mentionMap, :tweet)
            map = Map.put map, 'mentions', mentionMap
        end
        #{:noreply, map}
    end

    def handle_cast({:}) do
        {:noreply, map}
    end

    ##########################
    # Server Utility functions
    ##########################


end