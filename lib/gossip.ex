defmodule GSP do

  defp parse_args(args) do
    {_, str, _} = args |> OptionParser.parse
    str
  end

  def main(args) do
    str = args |> parse_args
    [numNodes, topology, algorithm] = str
    numNodes = String.to_integer(numNodes)

    pids = for node_id <- 0..numNodes-1 do
      GossipNode.new(%{node_id: node_id, sum: node_id, weight: 1, rumor_count: 0, master_pid: self(), history_queue: :queue.new, numNodes: numNodes, topology: topology})
    end

    #add links
    for node_id <- 0..numNodes-1 do
      node = Enum.at(pids, node_id)
      send node, {:add_neighbors, pids}
    end


    timeStart = :erlang.system_time #/ 1.0e6 |> Float.round 2 #
    case algorithm do
      "gossip" ->
      random = Enum.random(0..numNodes-1)
      send Enum.at(pids, random), :start_gossip
      "push-sum" ->
      random = Enum.random(0..numNodes-1)
      send Enum.at(pids, random), :start_push_sum
    end

    IO.puts "begin"
    wait_done(%{done_count: 0, numNodes: numNodes, timeStart: timeStart})


  end

  def wait_done(state) do
    receive do
      {pid, :done} ->
        new_done_count = state.done_count + 1
        IO.puts "Percentage complete: #{new_done_count / state.numNodes}"
        new_state = Map.put(state, :done_count, new_done_count)
        if new_done_count / state.numNodes > 0.95 do
          timeEnd = :erlang.system_time #/ 1.0e6 |> Float.round 2
          IO.puts "Time consumed: #{(timeEnd - state.timeStart) /1.0e3}"
          Process.exit(self(),:normal)
        end
        wait_done(new_state)
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
    pid = spawn_link fn ->
      Map.merge(@default_state, state) |> run
    end
  end

  def valid_location(locate_x, locate_y, true_sqrt, max_nodes) do
    locate_y + locate_x * true_sqrt < max_nodes and locate_y>= 0 and locate_y< true_sqrt
    and locate_x>= 0 and locate_x< true_sqrt
  end

  def create_neighbor(numNodes, topology, node_id) do
    case topology do
      "line" ->
        cond do
          node_id == 0 -> map = [node_id+1]
          node_id == numNodes-1 -> map = [node_id-1]
          true -> map = [node_id-1, node_id+1]
        end
      "2D" ->
        sqrt = :math.ceil(:math.sqrt(numNodes))
        map = []
        locate_x = :math.floor(node_id / sqrt)
        locate_y = node_id - locate_x * sqrt
        #left node
        if valid_location(locate_x, locate_y-1, sqrt, numNodes) do map = map ++ [round(locate_y-1 + locate_x * sqrt)] end
        #right node
        if valid_location(locate_x, locate_y+1, sqrt, numNodes) do map = map ++ [round(locate_y+1 + locate_x * sqrt)] end
        #upper node
        if valid_location(locate_x-1, locate_y, sqrt, numNodes) do map = map ++ [round(locate_y + (locate_x-1) * sqrt)] end
        #lower node
        if valid_location(locate_x+1, locate_y, sqrt, numNodes) do map = map ++ [round(locate_y + (locate_x+1) * sqrt)] end
      "full" ->
        map = for y <- 0..numNodes-1, y != node_id do y  end
      "imp2D" ->
        sqrt = :math.ceil(:math.sqrt(numNodes))
        map = []
        locate_x = :math.floor(node_id / sqrt)
        locate_y = node - locate_x * sqrt
        #left node
        if valid_location(locate_x, locate_y-1, sqrt, numNodes) do map = map ++ [round(locate_y-1 + locate_x * sqrt)] end
        #right node
        if valid_location(locate_x, locate_y+1, sqrt, numNodes) do map = map ++ [round(locate_y+1 + locate_x * sqrt)] end
        #upper node
        if valid_location(locate_x-1, locate_y, sqrt, numNodes) do map = map ++ [round(locate_y + (locate_x-1) * sqrt)] end
        #lower node
        if valid_location(locate_x+1, locate_y, sqrt, numNodes) do map = map ++ [round(locate_y + (locate_x+1) * sqrt)] end
        list = for x <- 0..numNodes-1 do x end -- [node_id]
        list = list -- map
        if length(list) != 0 do
          random_neighbor = Enum.random(list)
          map = map ++ [random_neighbor]
        end
    end
    map
  end

  defp run(state) do
    receive do
      :periodical ->
        random = Enum.random(0..length(state.neighbors)-1)
        select_neighbor = Enum.at(state.neighbors, random)
        send select_neighbor, :gossip
        Process.send_after(self(), :periodical, 1)
        run(state)

      :start_gossip ->
        new_rumor_count = state.rumor_count + 1
        new_state = Map.put(state, :rumor_count, new_rumor_count)
        random = Enum.random(0..length(state.neighbors)-1)
        select_neighbor = Enum.at(state.neighbors, random)

        send self(), :periodical
        run(new_state)

      :gossip ->
        new_rumor_count = state.rumor_count + 1
        new_state = Map.put(state, :rumor_count, new_rumor_count)

        if new_state.rumor_count == 10 do
          send new_state.master_pid, {self(), :done}
          Process.exit(self(), :normal)
        end

        send self(), :periodical

        run(new_state)

      :periodical_push ->
        new_sum = state.sum
        new_weight = state.weight
        new_state = Map.put(state, :sum, new_sum * 0.5)
        new_state = Map.put(new_state, :weight, new_weight*0.5)
        random = Enum.random(0..length(state.neighbors)-1)
        select_neighbor = Enum.at(state.neighbors, random)
        send select_neighbor, {:push_sum, new_sum*0.5, new_weight*0.5}

        Process.send_after(self(), :periodical_push, 5)
        run(new_state)

      :start_push_sum ->
        sum = state.sum
        weight = state.weight
        new_state = Map.put(state, :sum, sum * 0.5)
        new_state = Map.put(new_state, :weight, weight*0.5)
        IO.puts "hello"
        random = Enum.random(0..length(state.neighbors)-1)
        select_neighbor = Enum.at(state.neighbors, random)
        send select_neighbor, {:push_sum, sum*0.5, weight*0.5}

        send self(), :periodical_push
        run(new_state)

      {:push_sum, sum, weight} ->
        new_sum = state.sum + sum
        new_weight = state.weight + weight
        new_history_ratio = new_sum / new_weight
        history_queue = :queue.in(new_history_ratio, state.history_queue)

        if :queue.len(history_queue) == 3 do
          {{:value, first_value}, history_queue} = :queue.out(history_queue)
          second_value  = :queue.head(history_queue)
          third_value = :queue.daeh(history_queue)
          if abs(second_value-first_value) < 1.0e-10 and abs(second_value-third_value) < 1.0e-10   do
                send state.master_pid, {self(), :done}
                Process.exit(self(), :normal)
          end
        end

        new_state = Map.put(state, :sum, new_sum * 0.5)
        new_state = Map.put(new_state, :weight, new_weight * 0.5)
        new_state = Map.put(new_state, :history_queue, history_queue)


        random = Enum.random(0..length(state.neighbors)-1)
        select_neighbor = Enum.at(state.neighbors, random)
        send select_neighbor, {:push_sum, new_sum*0.5, new_weight*0.5}
        send self(), :periodical_push
        run(new_state)


      {:add_neighbors, pids} ->
        neighbor_map = create_neighbor(state.numNodes, state.topology, state.node_id)
        neighbors = for neighbor_id <- 0..length(neighbor_map)-1 do Enum.at(pids, Enum.at(neighbor_map, neighbor_id)) end
        new_state = Map.put(state, :neighbors, neighbors)
        run(new_state)
    end

  end
end
