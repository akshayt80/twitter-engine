defmodule Client do
    use GenServer

    def start_link() do
        # create clients and assign neigbors to them
        GenServer.start_link(__MODULE__, %{'tweets'=> [], 'subscribers'=> MapSet.new}, [])
    end

    def init(map) do
        {:ok, map}
    end
end