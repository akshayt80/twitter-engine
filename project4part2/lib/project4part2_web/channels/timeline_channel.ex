defmodule Project4part2Web.TimelineChannel do
  use Phoenix.Channel
  require Logger

  def join("timeline:feed", payload, socket) do
    Logger.info "incoming payload: #{inspect(payload)}"
    ServerUtil.insert_record(:users, {payload["username"], :online, MapSet.new, :queue.new, socket})
    ServerUtil.increase_counter("total_users")
    ServerUtil.increase_counter("online_users")
    {:ok, socket}
  end

  def handle_in("tweet", params, socket) do
    Logger.info "Received tweet message from websocket: #{inspect(params)}"

    tweet = params["tweet"]
    params = Map.put(params, "followers", ServerUtil.get_user_subscribers(params["username"]))
    components = SocialParser.extract(tweet,[:hashtags,:mentions])
    if Map.has_key? components, :hashtags do
        hashTagValues = components[:hashtags]
        for hashtag <- hashTagValues do
            Logger.debug "adding hashtag :#{hashtag} to hashtags table for tweet: #{tweet}"
            ServerUtil.add_hashtag_tweet(hashtag, tweet)
        end
    end
    mentionedUsers = []
    if Map.has_key?(components, :mentions) do
        mentionedUsers = components[:mentions]
        for user <- mentionedUsers do
            Logger.debug "adding mention: #{user} to mentions table for tweet: #{tweet}"
            ServerUtil.add_mention_tweet(user, tweet)
        end
        mentionedUsers = mentionedUsers |> Enum.reduce([], fn(x, acc) -> [List.first(String.split(x, ["@", "+"], trim: true)) |acc] end)
    end
    subscribers = ServerUtil.get_user_subscribers(params["username"])
    Logger.debug "subscribers: #{inspect(subscribers)}"
    if subscribers do
      for subscriber <- subscribers do
        status = ServerUtil.get_user_status(subscriber)
        if status != :online do
          ServerUtil.add_user_feed(subscriber, tweet)
        end
      end
    end
    params = Map.put(params, "mentions", mentionedUsers)
    broadcast_from! socket, "tweet", params
    {:noreply, socket}
  end

  def handle_in("subscribe", params, socket) do
    ServerUtil.add_user_subscibers(params["user"], params["username"])
    {:noreply, socket}
  end

  def handle_in("unsubscribe", params, socket) do
    ServerUtil.remove_user_subscriber(params["user"], params["username"])
    {:noreply, socket}
  end

  def handle_in("hashtag", params, socket) do
    tweets = ServerUtil.get_hashtag_tweets(params["hashtag"]) |> MapSet.to_list()
    {:reply, {:ok, %{"function"=> "hashtag", "tweets" => tweets, "username" => params["username"]}}, socket}
  end

  def handle_in("mention", params, socket) do
    tweets = ServerUtil.get_mention_tweets(params["mention"]) |> MapSet.to_list()
    {:reply, {:ok, %{"function"=> "mention", "tweets" => tweets, "username" => params["username"]}}, socket}
  end

  def handle_in("login", params, socket) do
    username = params["username"]
    ServerUtil.update_user_status(username, :online)
    feed = []
    if ServerUtil.user_has_feeds(username) do
      feed = ServerUtil.get_user_feed(username) |> :queue.to_list
      ServerUtil.empty_user_feed(username)
    end
    {:reply, {:ok, %{"function"=> "feed", "tweets" => feed, "username"=> username}}, socket}
  end

  def handle_in("logout", params, socket) do
    ServerUtil.update_user_status(params["username"], :offline)
    {:noreply, socket}
  end

end
