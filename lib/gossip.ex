defmodule GSP do

  defp parse_args(args) do
    {_, str, _} = args |> OptionParser.parse
    str
  end
  def valid_location(locate_x, locate_y, true_sqrt, max_nodes) do
    locate_y + locate_x * true_sqrt < max_nodes and locate_y>= 0 and locate_y< true_sqrt
    and locate_x>= 0 and locate_x< true_sqrt
  end

  def main(args) do
    str = args |> parse_args
    [numNodes, topology, algorithm] = str
    numNodes = String.to_integer(numNodes)
    case topology do

      "line" ->
      map = for x <- 0..numNodes-1 do
        cond do
          x == 0 -> [x+1]
          x == numNodes-1 -> [x-1]
          true -> [x-1, x+1]
        end
      end
      IO.inspect map

      "2D" ->
      sqrt = :math.ceil(:math.sqrt(numNodes))
      map = for x <- 0..numNodes-1 do
        temp_map = []
        locate_x = :math.floor(x / sqrt)
        locate_y = x - locate_x * sqrt
        #left node
        if valid_location(locate_x, locate_y-1, sqrt, numNodes) do temp_map = temp_map ++ [round(locate_y-1 + locate_x * sqrt)] end
        #right node
        if valid_location(locate_x, locate_y+1, sqrt, numNodes) do temp_map = temp_map ++ [round(locate_y+1 + locate_x * sqrt)] end
        #upper node
        if valid_location(locate_x-1, locate_y, sqrt, numNodes) do temp_map = temp_map ++ [round(locate_y + (locate_x-1) * sqrt)] end
        #lower node
        if valid_location(locate_x+1, locate_y, sqrt, numNodes) do temp_map = temp_map ++ [round(locate_y + (locate_x+1) * sqrt)] end
        temp_map
      end


      "full" ->
      map = for x <- 0..numNodes-1 do
        for y <- 0..numNodes-1, y != x do y  end
      end

      "imp2D" ->
      sqrt = :math.ceil(:math.sqrt(numNodes))
      map = for node <- 0..numNodes-1 do
        temp_map = []
        locate_x = :math.floor(node / sqrt)
        locate_y = node - locate_x * sqrt

        #left node
        if valid_location(locate_x, locate_y-1, sqrt, numNodes) do temp_map = temp_map ++ [round(locate_y-1 + locate_x * sqrt)] end
        #right node
        if valid_location(locate_x, locate_y+1, sqrt, numNodes) do temp_map = temp_map ++ [round(locate_y+1 + locate_x * sqrt)] end
        #upper node
        if valid_location(locate_x-1, locate_y, sqrt, numNodes) do temp_map = temp_map ++ [round(locate_y + (locate_x-1) * sqrt)] end
        #lower node
        if valid_location(locate_x+1, locate_y, sqrt, numNodes) do temp_map = temp_map ++ [round(locate_y + (locate_x+1) * sqrt)] end
        list = for x <- 0..numNodes-1 do x end -- [node]
        list = list -- temp_map
        if length(list) != 0 do
          random_neighbor = Enum.random(list)
          temp_map = temp_map ++ [random_neighbor]
        end
        temp_map
      end
    end

    #initial nodes
    pids = for node_id <- 0..numNodes-1 do
      pid = GossipNode.new(%{node_id: node_id, rumor_count: 0, master_pid: self()})
    end
    IO.inspect pids
    IO.inspect map
    #add links
    for node_id <- 0..numNodes-1 do
      node = Enum.at(pids, node_id)
      neighbor_map = Enum.at(map, node_id)
      neighbors = for neighbor_id <- 0..length(neighbor_map)-1 do Enum.at(pids, Enum.at(neighbor_map, neighbor_id)) end
      send(node, {:add_neighbors, neighbors})
    end

    case algorithm do
      "gossip" ->
      send Enum.at(pids, 0), :hello
      "line" ->
      IO.puts "hello"
    end

    wait_done()


  end

  def wait_done(done_count \\ 0) do
    receive do
      :done ->
      done_count = done_count + 1
      IO.puts done_count
      if done_count == 10 do
        IO.puts "finished"
        Process.exit(self(), :kill)
      end
    
    end
  end

end

defmodule GossipNode do
  @default_state %{
    node_id: -1,
    rumor_count: 0,
    neighbors: [],
  }

  def new(state \\ %{}) do
    spawn_link fn ->
      Map.merge(@default_state, state) |> run
    end
  end

  defp run(state) do
    receive do
      :hello ->
      new_rumor_count = state.rumor_count + 1
      new_state = Map.put(state, :rumor_count, new_rumor_count)
      cond do
        new_rumor_count < 10 ->
          random = Enum.random(0..length(new_state.neighbors)-1)
          select_neighbor = Enum.at(new_state.neighbors, random)
          send select_neighbor, :hello
          run(new_state)
        new_rumor_count == 10 ->
          send new_state.master_pid, :done
      end



      {:add_neighbors, neighbors} ->
      new_state = Map.put(state, :neighbors, neighbors)
      run(new_state)
    end
  end

end
