# Test file with performance and correctness issues for Azure DevOps review

class DataProcessor
  # Performance Issue: N+1 query problem
  def process_users(user_ids)
    user_ids.each do |id|
      user = User.find(id)  # Database query in loop
      posts = user.posts    # Another query for each user
      puts "#{user.name}: #{posts.count} posts"
    end
  end

  # Performance Issue: String concatenation in loop
  def build_report(records)
    report = ""
    records.each do |record|
      report += "#{record.id},#{record.name}\n"  # Creates new string each time
    end
    report
  end

  # Performance Issue: Inefficient nested loops (O(n*m))
  def find_duplicates(list_a, list_b)
    matches = []
    list_a.each do |item_a|
      list_b.each do |item_b|
        matches << item_a if item_a == item_b
      end
    end
    matches
  end

  # Correctness Issue: Type coercion problem
  def check_admin(user)
    return user.role == "admin"  # Should use === in some contexts
  end

  # Performance Issue: Loading all records into memory
  def send_notifications
    User.all.each do |user|  # Should use find_each for batching
      send_email(user)
    end
  end

  # Correctness Issue: Missing error handling
  def calculate_average(numbers)
    total = numbers.sum
    count = numbers.length
    total / count  # Will crash if numbers is empty
  end
end
