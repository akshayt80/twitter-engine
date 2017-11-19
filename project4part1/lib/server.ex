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
        {:noreply, map}
    end

    ##########################
    # Server Utility functions
    ##########################

    defp add_in_set(set, value) do
        MapSet.put set, value
    end

    defp enqueue(queue, value) do
        if :queue.member value, q do
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

    defp loop(list, last, map, tweet, current//None) do
        [current| list] = list
        set = Map.get(map, current) |> MapSet.put tweet
        map = Map.put map, current, set
        loop(list, last, map, current)
    end
end
