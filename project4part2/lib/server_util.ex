defmodule ServerUtil do
    require Logger

    def update_counter(field, factor) do
        :ets.update_counter(:counter, field, factor)
    end

    def increase_counter(field) do
        update_counter(field, 1)
    end

    def decrease_counter(field) do
        update_counter(field, -1)
    end

    def member_of_mentions(mention) do
        :ets.member(:mentions, mention)
    end

    def get_mention_tweets(mention) do
        if member_of_mentions(mention) do
            :ets.lookup_element(:mentions, mention, 2)
        else
            MapSet.new
        end
    end

    def add_mention_tweet(mention, tweet) do
        mentions = :ets.lookup(:mentions, mention)
        if mentions != [] do
            updated_mentions = mentions |> List.first |> elem(1) |> MapSet.put(tweet)
            insert_record(:mentions, {mention, updated_mentions})
        else
            tweets = MapSet.new |> MapSet.put(tweet)
            insert_record(:mentions, {mention, tweets})
        end
    end

    def send_mentions(mention, client, username) do
        tweets = get_mention_tweets(mention) |> MapSet.to_list()
        Logger.debug "sending mentions: #{inspect(tweets)}"
        data = %{"function"=> "mention", "tweets" => tweets, "username" => username}
        #send_response(client, data)
        :timer.sleep 20
    end

    def member_of_hashtags(hashtag) do
        :ets.member(:hashtags, hashtag)
    end

    def get_hashtag_tweets(hashtag) do
        if member_of_hashtags(hashtag) do
            :ets.lookup_element(:hashtags, hashtag, 2)
        else
            MapSet.new
        end
    end

    def add_hashtag_tweet(hashtag, tweet) do
        hashtags = :ets.lookup(:hashtags, hashtag)
        if hashtags != [] do
            updated_tweets = hashtags |> List.first |> elem(1) |> MapSet.put(tweet)
            insert_record(:hashtags, {hashtag, updated_tweets})
        else
            tweets = MapSet.new |> MapSet.put(tweet)
            insert_record(:hashtags, {hashtag, tweets})
        end
    end

    def send_hashtags(hashtag, client, username) do
        tweets_chunks = get_hashtag_tweets(hashtag) |> MapSet.to_list() |> Enum.chunk_every(5)
        for tweets <- tweets_chunks do
            data = %{"function"=> "hashtag", "tweets" => tweets, "username" => username}
            #send_response(client, data)
            :timer.sleep 20
        end
    end

    def member_of_users(username) do
        :ets.member(:users, username)
    end

    def insert_record(table, tuple) do
        :ets.insert(table, tuple)
    end

    def user_has_feeds(username) do
        feed = get_user_feed(username)
        if feed == :queue.new do
          false
        else
          true
        end
    end

    def send_feed(username, client) do
        feeds = get_user_feed(username) |> :queue.to_list |> Enum.chunk_every(5)
        for feed <- feeds do
            data = %{"function"=> "feed", "feed" => feed, "username"=> username}
            #send_response(client, data)
            :timer.sleep 50
        end
        empty_user_feed(username)
    end

    def get_user(username) do
        record = :ets.lookup(:users, username)
        if record == [] do
          false
        else
          List.first(record)
        end
    end

    def get_user_field(username, pos) do
        user = get_user(username)
        if user != false do
          user |> elem(pos)
        else
          false
        end
    end

    def get_user_status(username) do
        #{status, subscribers, feed}
        get_user_field(username, 1)
    end

    def get_user_subscribers(username) do
        get_user_field(username, 2)
    end

    def get_user_feed(username) do
        get_user_field(username, 3)
    end

    def get_user_port(username) do
        get_user_field(username, 4)
    end

    def update_user_field(username, pos, value) do
        :ets.update_element(:users, username, {pos, value})
    end

    def update_user_status(username, status) do
        update_user_field(username, 2, status)
    end

    def add_user_subscibers(username, subscriber) do
        # assuming the user to be there in table
        subs = get_user_subscribers(username) |> MapSet.put(subscriber)
        Logger.debug "user: #{username} updated subs: #{inspect(subs)}"
        update_user_field(username, 3, subs)
    end

    def add_bulk_user_subscribers(username, follwers) do
        existing_subs = get_user_subscribers(username)
        subs = MapSet.union(existing_subs, MapSet.new(follwers))
        update_user_field(username, 3, subs)
    end

    def remove_user_subscriber(username, subscriber) do
        subs = get_user_subscribers(username) |> MapSet.delete(subscriber)
        update_user_field(username, 3, subs)
    end

    def add_user_feed(username, tweet) do
        feed = get_user_feed(username)
        if feed do
            Logger.debug "#{username}'s feed: #{inspect(feed)}"
            feed = enqueue(feed, tweet)
            Logger.debug "#{username}'s updated feed: #{inspect(feed)}"
            update_user_field(username, 4, feed)
        end
    end

    def empty_user_feed(username) do
        update_user_field(username, 4, :queue.new)
    end

    def update_socket(username, socket) do
        update_user_field(username, 5, socket)
    end

    defp enqueue(queue, value) do
        if :queue.member(value, queue) do
            queue
        else
            :queue.in(value, queue)
        end
    end
end