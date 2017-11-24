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
        start_communication(socket, self())
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

    defp send_message(receiver, data) do
        encoded_response = Poison.encode!(data)
        :gen_tcp(receiver, encoded_response)
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

    def handle_cast({:tweet}, map) do
        {:noreply, map}
    end

    ####################

    defp perform_logout(server) do
        # send logout message
        # sleep for some random time between 1 to 10 sec
        # send login back to server
        # print the feed
    end

    defp perform_registration(server) do
        # pick a username
        # send register message to server
        # send login message to server
        # send subscriber message to server
    end

    defp received_tweet(server) do
        # print tweet
        # with probability od 20% do retweet
    end

    defp query_server(server) do
        # no need to do this in simulator
        # send message to server to get metions
        # print all the tweets with mention
        # send message to server to get hashtags
        # print all the tweets with hashtag
    end
end
