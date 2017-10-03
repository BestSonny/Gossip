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

    pids = for node_id <- 0..numNodes-1 do
      GossipNode.new(%{node_id: node_id, sum: node_id, weight: 1, rumor_count: 0, master_pid: self(), history_queue: :queue.new, done_push: 0})
    end


    #add links
    for node_id <- 0..numNodes-1 do
      node = Enum.at(pids, node_id)
      neighbor_map = Enum.at(map, node_id)
      neighbors = for neighbor_id <- 0..length(neighbor_map)-1 do Enum.at(pids, Enum.at(neighbor_map, neighbor_id)) end
      send node, {:add_neighbors, neighbors}
    end


    timeStart = :erlang.system_time / 1.0e6 |> round
    case algorithm do
      "gossip" ->
      random = Enum.random(0..numNodes-1)
      send Enum.at(pids, random), :start_gossip
      "push-sum" ->
      random = Enum.random(0..numNodes-1)
      send Enum.at(pids, random), :start_push_sum
    end


    wait_done(%{done_count: 0, numNodes: numNodes, timeStart: timeStart})


  end

  def wait_done(state) do
    receive do
      {pid, :done} ->
        new_done_count = state.done_count + 1
        IO.puts "Percentage complete: #{new_done_count / state.numNodes}"
        new_state = Map.put(state, :done_count, new_done_count)
        if new_done_count / state.numNodes > 0.9 do
          timeEnd = :erlang.system_time / 1.0e6 |> round
          IO.puts "Time consumed: #{timeEnd - state.timeStart}"
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
    IO.inspect Map.merge(@default_state, state)
    pid = spawn_link fn ->
      Map.merge(@default_state, state) |> run
    end
  end

  defp run(state) do
    receive do
      :periodical ->
        random = Enum.random(0..length(state.neighbors)-1)
        select_neighbor = Enum.at(state.neighbors, random)
        send select_neighbor, :gossip
        Process.send_after(self(), :periodical, 100)
        run(state)

      :start_gossip ->
        random = Enum.random(0..length(state.neighbors)-1)
        select_neighbor = Enum.at(state.neighbors, random)
        send select_neighbor, :gossip
        send self(), :periodical
        run(state)

      :gossip ->
        new_rumor_count = state.rumor_count + 1
        new_state = Map.put(state, :rumor_count, new_rumor_count)

        if new_state.rumor_count == 10 do
          send new_state.master_pid, {self(), :done}
          Process.exit(self(),:normal)
        end

        random = Enum.random(0..length(new_state.neighbors)-1)
        select_neighbor = Enum.at(new_state.neighbors, random)
        send select_neighbor, :gossip
        send self(), :periodical

        run(new_state)

      :start_push_sum ->
        new_sum = state.sum / 2.0
        new_weight = state.weight / 2.0
        history_ratio = new_sum/new_weight

        history_queue = :queue.in(history_ratio, state.history_queue)
        new_state = Map.put(state, :sum, new_sum)
        new_state = Map.put(new_state, :weight, new_weight)
        new_state = Map.put(new_state, :history_queue, history_queue)

        random = Enum.random(0..length(state.neighbors)-1)
        select_neighbor = Enum.at(new_state.neighbors, random)
        send select_neighbor, {:push_sum, new_sum, new_weight}

        run(new_state)

      {:push_sum, sum, weight} ->
        new_sum = state.sum + sum
        new_weight = state.weight + weight
        new_history_ratio = new_sum / new_weight
        history_queue = :queue.in(new_history_ratio, state.history_queue)
        if state.done_push == 0 do
          if :queue.len(history_queue) == 3 do
            {{:value, first_value}, history_queue} = :queue.out(history_queue)
            third_value = :queue.head(history_queue)
            if abs(third_value-first_value) < 1.0e-10 do
              send state.master_pid, {self(), :done}
              state = Map.put(state, :done_push, 1)
            end
          end

          new_state = Map.put(state, :sum, new_sum / 2.0)
          new_state = Map.put(new_state, :weight, new_weight / 2.0)
          new_state = Map.put(new_state, :history_queue, history_queue)

          random = Enum.random(0..length(state.neighbors)-1)
          select_neighbor = Enum.at(new_state.neighbors, random)
          send select_neighbor, {:push_sum, new_sum / 2.0, new_weight / 2.0}
          run(new_state)
        else
          random = Enum.random(0..length(state.neighbors)-1)
          select_neighbor = Enum.at(state.neighbors, random)
          send select_neighbor, {:push_sum, sum, weight}
          run(state)
        end

      {:add_neighbors, neighbors} ->
        new_state = Map.put(state, :neighbors, neighbors)
        run(new_state)


    end
  end

end
