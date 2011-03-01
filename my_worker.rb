class MyWorker < JobQueue::JobWorker
  def run
    (1..200).each do |n|
      puts n
      sleep(n/200)
    end
    42
  end
end

if __FILE__ == $0
  MyWorker.new.run
end
