defmodule BCM.Supervisor do

  @default_server_port Application.get_env :project, :port, 6666
  @local_host Application.get_env :project, :ip, {127,0,0,1}

  def launch_server do
    IO.puts @default_server_port
    launch_server(@default_server_port)
  end

  def launch_server(port) do
    IO.puts "Launching server on localhost on port #{port}"
    server = Socket.UDP.open!(port)
    serve(server)
  end

  def serve(server) do
    {data, client} = server |> Socket.Datagram.recv!
    IO.puts "#{data}, from #{inspect(client)}"
    serve(server)
  end

  def spawn_link(prefix_number) do
    spawn_link(__MODULE__, :init, [prefix_number])
  end

  def init_client(ip_address) do
    Process.flag :trap_exit, true
    children_pids = Enum.map(ip_address, fn(ip_address) ->
    pid = run_client_worker(ip_address)
    {pid, ip_address} end) |> Enum.into(%{})
    loop_client(children_pids)
  end

  def loop_client(client_pids) do
    receive do
      {:EXIT, pid, _} = msg->
        {ip_address, client_pids} = pop_in client_pids[pid]
        new_pid = run_client_worker(ip_address)
        client_pids = put_in client_pids[new_pid], ip_address
        loop_client(client_pids)
    end
  end

  def init_server(prefix_number) do
    Process.flag :trap_exit, true
    task = Task.async(fn ->  launch_server end)
    server_worker_pids = Enum.map(prefix_number, fn(prefix_number) ->
    pid = run_server_worker(prefix_number)
    {pid, prefix_number} end) |> Enum.into(%{})
    loop_server(server_worker_pids)
    Task.await(task)
  end

  def loop_server(server_worker_pids) do
    receive do
      {:EXIT, pid, _} = msg->
        #IO.puts "Parent got message: #{inspect msg}"

        {prefix_number, server_worker_pids} = pop_in server_worker_pids[pid]
        new_pid = run_server_worker(prefix_number)

        server_worker_pids = put_in server_worker_pids[new_pid], prefix_number

        #IO.puts "Restart children #{inspect pid}(prefix_number #{prefix_number}) with new pid #{inspect new_pid}"
        loop_server(server_worker_pids)
    end
  end

  def run_server_worker(prefix_number) do
    spawn_link(Child, :init, [prefix_number])
  end

  def run_client_worker(ip_address) do
    spawn_link(Child, :init_for_remote, [ip_address])
  end

end

defmodule Child do

  @default_server_port Application.get_env :project, :port, 6666
  @local_host Application.get_env :project, :ip, {127,0,0,1}

  defp hash_match(number) do
    prefix_zeros = String.duplicate("0", number)
    random_string = :crypto.strong_rand_bytes(10) |> Base.encode64 |> binary_part(0, 10)
    prefix = "13137866,"
    hash_code = :crypto.hash(:sha256, prefix <> random_string) |> Base.encode16
    if String.equivalent?(String.slice(hash_code, 0..(number-1)), prefix_zeros) do
      prefix <> random_string <> " " <> hash_code
    else
      "AAAA"
    end
  end

  def init(prefix_number) do
    result = hash_match(prefix_number)
    if String.equivalent?(result, "AAAA") == false do
      send_data("Pan He "<>result, {@local_host, @default_server_port})
    end
  end

  def init_for_remote(ip_address) do
    result = hash_match(4)
    if String.equivalent?(result, "AAAA") == false do
      send_data("Xiaohui Huang "<>result, {ip_address, @default_server_port})
    end
  end

  def send_data(data, to) do
    server = Socket.UDP.open!  # Without specifying the port, we randomize it
    Socket.Datagram.send!(server, data, to)
  end
end

defmodule BCM do

  def to_list(ip) do
    segments = String.split(ip, ".") # ["10", "0", "0", "1"]
    for segment <- segments, do: String.to_integer(segment) # [10,0,0,1]
  end

  def is_ipv4?(ip) do
    case Regex.match?(~r/^(\d{1,3}\.){3}\d{1,3}$/, ip) do
      false -> false
      true -> ip |> to_list |> Enum.any?(fn(x) -> x > 255 end) |> Kernel.not
    end
  end

  defp parse_args(args) do
    {_, [str], _} = args |> OptionParser.parse
    str
  end

  def main(args) do
    str = args |> parse_args
    cond do
        is_ipv4?(str) == true -> BCM.Supervisor.init_client([str, str])
        str |> String.to_integer > 0 ->
          prefix_number = str |> String.to_integer
          BCM.Supervisor.init_server([prefix_number, prefix_number])
    end
  end
end
