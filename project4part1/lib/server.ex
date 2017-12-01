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
        initialize_counters()
        #:ets.insert(:counter, {"tweets", 0})
        # using this to store map of user and port
        GenServer.start_link(__MODULE__, {MapSet.new, listen_socket}, name: :myServer)
        spawn fn -> stats_print() end
        loop_acceptor(listen_socket)
        #keep_alive()
    end
    
    def keep_alive() do
        :timer.sleep 10000
        keep_alive()
    end

    defp initialize_counters() do
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

    defp loop_acceptor(socket) do
        Logger.debug "Ready to accept new connections"
        {:ok, worker} = :gen_tcp.accept(socket)
        incomplete_packet = :ets.new(:incomplete_packet, [:set, :public, read_concurrency: true])
        # Spawn receive message in separate process
        spawn fn -> serve(worker, incomplete_packet) end
        # Loop to accept new connection
        loop_acceptor(socket)
    end

    defp serve(worker, incomplete_packet) do
        # TODO:- handle errors {:error, :closed}
        {status, response} = :gen_tcp.recv(worker, 0)
        if status == :ok do
            # this will handle the case when there are more than one
            Logger.debug "Socket data: #{inspect(response)}"
            multiple_data = response |> String.split("}", trim: :true)
            for data <- multiple_data do
                Logger.debug "data to be decoded: #{inspect(data)}"
                incomplete_packet_data = get_incomplete_packet(incomplete_packet)
                if incomplete_packet_data != false do
                    data = "#{incomplete_packet_data}#{data}"
                    Logger.debug "Found incomplete_packet and modified to: #{data}"
                end
                try do
                    data = Poison.decode!("#{data}}")
                    Logger.debug "received data from worker #{inspect(worker)} data: #{inspect(data)}"

                    # Send value of k as String
                    #Logger.debug "sending initial message"
                    #:gen_tcp.send(worker, "Welcome to the Twitter")
                    #GenServer.cast(:myServer, {:initial, data, worker})
                    case Map.get(data, "function") do
                       "register" -> GenServer.cast(:myServer, {:register, data["username"], worker})
                       "login" -> GenServer.cast(:myServer, {:login, data["username"], worker})
                       "logout" -> GenServer.cast(:myServer, {:logout, data["username"]})
                       "hashtag" -> GenServer.cast(:myServer, {:hashtag, data["hashtag"], data["username"], worker})
                       "mention" -> GenServer.cast(:myServer, {:mention, data["mention"], data["username"], worker})
                       "tweet" -> GenServer.cast(:myServer, {:tweet, data["username"], data["tweet"]})
                       "subscribe" -> GenServer.cast(:myServer, {:subscribe, data["username"], data["users"]})
                       "unsubscribe" -> GenServer.cast(:myServer, {:unsubscribe, data["username"], data["users"]})
                       "bulk_subscription" -> GenServer.cast(:myServer, {:bulk_subscription, data["username"], data["users"]})
                       _ -> Logger.error "unmatched clause for data: #{inspect(data)}"
                    end
                rescue
                    Poison.SyntaxError -> Logger.debug "Got poison error for data: #{data}"
                    insert_incomplete_packet(data, incomplete_packet)
                end
            end
        end
        serve(worker, incomplete_packet)
    end

    defp send_response(client, data) do
        # TODO:- Decide whether we want to update counter for feed as well
        encoded_response = Poison.encode!(data)
        :gen_tcp.send(client, encoded_response)
    end

    def init(set) do
        #GenServer.cast(self(), {:accept})
        {:ok, set}
    end

    def handle_cast({:accept}, state) do
        {:ok, worker} = :gen_tcp.accept(elem(state, 1))
        {:noreply, state}
    end

    def handle_cast({:register, username, client}, state) do
        # if username unique then send ok
        # else send :error
        user = get_user(username)
        socket = elem(state, 1)
        set = elem(state, 0)
        # TODO:- registeredUser set becomes redundant as we have userid in main map
        if user != false do
            #{:reply, {:error, "already exists"}, map}
            send_response(client, %{"function"=> "register", "username"=> username, "status"=> "error", "message"=> "Username already exists"})
        else
            Logger.debug "added new user to set"
            set = set |> MapSet.put(username)
            #currentRegisteredUsers = map["registeredUsers"]
            #updatedRegisteredUsers = MapSet.put(currentRegisteredUsers, username)
            # {username, status, subscribers, feed, port}
            insert(username, :online, MapSet.new, :queue.new, client)
            # map = Map.put(map, username, %{
            #                         "subscribers" => MapSet.new,
            #                         "feed" => :queue.new,
            #                         "port" => client
            #                     }
            #                 )
            # map = Map.put(map, "registeredUsers", updatedRegisteredUsers)
            #send_response(client, %{"function"=> "register", "status"=> "success", "message"=> "Added new user", "users"=> set})
            update_counter("total_users")
            update_counter("online_users")
            #{:reply, {:ok, "success"}, Map.put(map, "registeredUsers", registeredUsers)}
        end
        {:noreply, {set, socket}}
    end

    def handle_cast({:login, username, client}, set) do
        # online_set = map['online']
        # offline_set = map['offline']
        # if MapSet.member?(offline_set, username) do
        #     offline_set = MapSet.delete(offline_set, username)
        #     # TODO:- send the messages accumulated at the server asyncly while the client was offline
        # end
        # online_set = MapSet.put(online_set, username)
        # temp_dict = %{'online' => online_set, 'offline' => offline_set}
        # map = Map.merge(map, temp_dict) 
        #{:reply, {:ok, "success"}, map}
        if member_of_users(username) do
            offline_users = :ets.lookup_element(:counter, "offline_users", 2)
            if offline_users > 0 do
                decrease_counter("offline_users")
            end
            update_user_status(username, :online)
            if user_has_feeds(username) do
                Logger.debug "#{username} has some tweets in feed"
                spawn fn ->  send_feed(username, client) end
                #empty_user_feed(username)
            end
            update_counter("online_users")
        end
        {:noreply, set}
    end

    def handle_cast({:logout, username}, set) do
        # online_set = map['online']
        # offline_set = map['offline']
        # if MapSet.member?(online_set, username) do
        #     online_set = MapSet.delete(online_set, username)
        # end
        # offline_set = MapSet.put(offline_set, username)
        # temp_dict = %{'online' => online_set, 'offline' => offline_set}
        # map = Map.merge(map, temp_dict) 
        #{:reply, {:ok, "success"}, map}
        if member_of_users(username) do
            update_user_status(username, :offline)
            update_counter("offline_users")
            decrease_counter("online_users")
        end
        {:noreply, set}
    end

    def handle_cast({:hashtag, hashtag, username, client}, map) do
        # hashtags = map["hashtags"]
        # if Map.has_key? hashtags, hashtag do
        #     # TODO:- see how to send a list as bytes in elixir
        #     #{:reply, {:hashtag, Map.get(hashtags, hashtag)}, map}
        #     {:noreply, map}

        # else
        #     #{:reply, {:nohashtag, "None"}, map}
        #     {:noreply, map}

        # end
        Logger.debug "sending tweets containing hashtag: #{hashtag} to user: #{username}"
        #hashtags = get_hashtag_tweets(hashtag)
        spawn fn -> send_hashtags(hashtag, client, username) end
        {:noreply, map}
    end

    def handle_cast({:mention, mention, username, client}, map) do
        # mentions = map["mentions"]
        # if Map.has_key? mentions, name do
        #     # TODO:- see how to send a list as bytes in elixir
        #     #{:reply, {:mention, Map.get(mentions, name)}, map}
        #     {:noreply, map}
        # else
        #     #{:reply, {:nomention, "None"}, map}
        #     {:noreply, map}
        # end
        Logger.debug "sending tweets containing mention: #{mention} to user: #{username}"
        #mentions = get_mention_tweets(mention)
        spawn fn -> send_mentions(mention, client, username) end
        {:noreply, map}
    end

    def handle_cast({:tweet, username, tweet}, map) do
        # hashTagMap = Map.get map, 'hashtags'
        # mentionMap = Map.get map, 'mentions'
        mentionedUsers = None
        components = SocialParser.extract(tweet,[:hashtags,:mentions])
        if Map.has_key? components, :hashtags do
            hashTagValues = Map.get(components, :hashtags)
            #hashTagMap = loop(hashTagValues, List.last(hashTagValues), hashTagMap, tweet)
            #map = Map.put map, 'hashtags', hashTagMap
            for hashtag <- hashTagValues do
                Logger.debug "adding hashtag :#{hashtag} to hashtags table for tweet: #{tweet}"
                add_hashtag_tweet(hashtag, tweet)
            end
        end

        if Map.has_key? components, :mentions do
            mentionedUsers = Map.get(components, :mentions)
            # mentionMap = loop(mentionValues, List.last(mentionValues), mentionMap, tweet)
            # map = Map.put map, 'mentions', mentionMap
            
            for user <- mentionedUsers do
                Logger.debug "adding mention: #{user} to mentions table for tweet: #{tweet}"
                add_mention_tweet(user, tweet)
                value = String.split(user, ["@", "+"], trim: true) |> List.first
                port = get_user_port(value)
                status = get_user_status(value)
                if value != username do
                    update_counter("tweets")
                    if status == :online do
                        Logger.debug "Sending to: #{value} tweet: #{tweet}"
                        send_response(port, %{"function"=> "tweet", "sender"=> username, "tweet"=> tweet, "username"=> value})
                    else
                        Logger.debug "Adding to user feed as #{value} is not online"
                        add_user_feed(value, tweet)
                    end
                end
            end
        end
        # sender = get_user(username)
        subscribers = get_user_subscribers(username)
        for subscriber <- subscribers do
            # user_info = map[subscriber]
            #port = user_info['port']
            Logger.debug "mentioned_users: #{inspect(mentionedUsers)}"
            if mentionedUsers != None and Enum.member?(mentionedUsers, subscriber) do
                Logger.debug "Not sending the message again"
            else
                port = get_user_port(subscriber)
                status = get_user_status(subscriber)
                if status == :online do
                    Logger.debug "Sending to: #{subscriber} tweet: #{tweet}"
                    send_response(port, %{"function"=> "tweet", "sender"=> username, "tweet"=> tweet, "username"=> subscriber})
                else
                    Logger.debug "Adding to user feed as #{subscriber} is not online"
                    add_user_feed(subscriber, tweet)
                end
                update_counter("tweets")
            end
        end

        {:noreply, map}
    end

    def handle_cast({:subscribe, username, follow}, map) do
        #TODO:- using ets follow expected to be list of people user want to follow
        # user = map[follow]
        # user_subscribers = user['subscribers']
        # updated_subscribers = MapSet.put(user_subscribers, username)
        # updated_user = Map.put(user, 'subscribers', updated_subscribers)
        # map = Map.put(map, follow, updated_user)
        for sub <- follow do
            Logger.debug "subscribing user: #{username} to: #{sub}"
            add_user_subscibers(sub, username)
        end
        {:noreply, map}
    end

    def handle_cast({:bulk_subscription, username, follwers}, map) do
        Logger.debug "adding bulk followers for user: #{username}"
        add_bulk_user_subscribers(username, follwers)
        {:noreply, map}
    end

    def handle_cast({:unsubscribe, username, unsubscribe}, map) do
        for unsub <- unsubscribe do
            remove_user_subscriber(unsub, username)
        end
        {:noreply, map}
    end

    def handle_info({:tcp, socket, msg}, map) do
        Logger.debug "Incoming message: #{msg}"
        {:noreply, map}
    end

    ##########################
    # Server Utility functions
    ##########################

    defp insert_incomplete_packet(data, table)do
       :ets.insert(table, {"incomplete_packet", data})
    end

    defp get_incomplete_packet(table) do
        packet = false
        if :ets.member(table, "incomplete_packet") do
            packet = :ets.lookup_element(table, "incomplete_packet", 2)
            :ets.delete(table, "incomplete_packet")
        end
        packet
    end

    defp update_counter(field) do
        :ets.update_counter(:counter, field, 1)
    end

    defp decrease_counter(field) do
        :ets.update_counter(:counter, field, -1)
    end

    defp member_of_mentions(mention) do
        :ets.member(:mentions, mention)
    end

    defp get_mention_tweets(mention) do
        if member_of_mentions(mention) do
            :ets.lookup(:mentions, mention) |> List.first |> elem(1) # |> MapSet.to_list()
        else
            MapSet.new
        end
    end

    defp add_mention_tweet(mention, tweet) do
        mentions = :ets.lookup(:mentions, mention)
        if mentions != [] do
            updated_mentions = mentions |> List.first |> elem(1) |> MapSet.put(tweet)
            :ets.insert(:mentions, {mention, updated_mentions})
        else
            tweets = MapSet.new |> MapSet.put(tweet)
            :ets.insert(:mentions, {mention, tweets})
        end
    end

    defp send_mentions(mention, client, username) do
        tweets = get_mention_tweets(mention) |> MapSet.to_list() |> Enum.chunk_every(5)
        Logger.debug "sending mentions: #{inspect(tweets)}"
        for tweet <- tweets do
            data = %{"function"=> "mention", "tweets" => tweets, "username" => username}
            send_response(client, data)
            :timer.sleep 20
        end
    end

    defp member_of_hashtags(hashtag) do
        :ets.member(:hashtags, hashtag)
    end

    defp get_hashtag_tweets(hashtag) do
        if member_of_hashtags(hashtag) do
            :ets.lookup(:hashtags, hashtag)|> List.first |> elem(1) #|> MapSet.to_list()
        else
            MapSet.new
        end
    end

    defp add_hashtag_tweet(hashtag, tweet) do
        hashtags = :ets.lookup(:hashtags, hashtag)
        if hashtags != [] do
            updated_tweets = hashtags |> List.first |> elem(1) |> MapSet.put(tweet)
            :ets.insert(:hashtags, {hashtag, updated_tweets})
        else
            tweets = MapSet.new |> MapSet.put(tweet)
            :ets.insert(:hashtags, {hashtag, tweets})
        end
    end

    defp send_hashtags(hashtag, client, username) do
        tweets = get_hashtag_tweets(hashtag) |> MapSet.to_list() |> Enum.chunk_every(5)
        for tweet <- tweets do
            data = %{"function"=> "hashtag", "tweets" => tweets, "username" => username}
            send_response(client, data)
            :timer.sleep 20
        end
    end

    defp member_of_users(username) do
        :ets.member(:users, username)
    end

    defp insert(username, status, subscribers, feed, port) do
        :ets.insert(:users, {username, status, subscribers, feed, port})
    end

    defp user_has_feeds(username) do
        feed = get_user_feed(username)
        if feed == :queue.new do
          false
        else
          true
        end
    end

    defp send_feed(username, client) do
        feeds = get_user_feed(username) |> :queue.to_list |> Enum.chunk_every(5)
        for feed <- feeds do
            data = %{"function"=> "feed", "feed" => feed, "username"=> username}
            send_response(client, data)
            :timer.sleep 50
        end
        empty_user_feed(username)
    end

    defp get_user(username) do
        record = :ets.lookup(:users, username)
        if record == [] do
          false
        else
          List.first(record)
        end
    end

    defp get_user_field(username, pos) do
        user = get_user(username)
        if user != false do
          user |> elem(pos)
        else
          false
        end
    end

    defp get_user_status(username) do
        #{status, subscribers, feed}
        get_user_field(username, 1)
    end

    defp get_user_subscribers(username) do
        get_user_field(username, 2)
    end

    defp get_user_feed(username) do
        get_user_field(username, 3)
    end

    defp get_user_port(username) do
        get_user_field(username, 4)
    end

    defp update_user_field(username, pos, value) do
        :ets.update_element(:users, username, {pos, value})
    end

    defp update_user_status(username, status) do
        update_user_field(username, 2, status)
    end

    defp add_user_subscibers(username, subscriber) do
        # assuming the user to be there in table
        subs = get_user_subscribers(username) |> MapSet.put(subscriber)
        Logger.debug "user: #{username} updated subs: #{inspect(subs)}"
        update_user_field(username, 3, subs)
    end

    defp add_bulk_user_subscribers(username, follwers) do
        existing_subs = get_user_subscribers(username)
        subs = MapSet.union(existing_subs, MapSet.new(follwers))
        update_user_field(username, 3, subs)
    end

    defp remove_user_subscriber(username, subscriber) do
        subs = get_user_subscribers(username) |> MapSet.delete(subscriber)
        update_user_field(username, 3, subs)
    end

    defp add_user_feed(username, tweet) do
        feed = get_user_feed(username)
        if feed do
            Logger.debug "#{username}'s feed: #{inspect(feed)}"
            feed = enqueue(feed, tweet)
            Logger.debug "#{username}'s updated feed: #{inspect(feed)}"
            update_user_field(username, 4, feed)
        end
    end

    defp empty_user_feed(username) do
        update_user_field(username, 4, :queue.new)
    end

    defp enqueue(queue, value) do
        if :queue.member(value, queue) do
            queue
        else
            :queue.in(value, queue)
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
