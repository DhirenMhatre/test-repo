# Test file for performance issues
# Should trigger warnings when priority is "N+1 queries" or "String concatenation in loops"

class ReportGenerator
  # Bad: N+1 query pattern
  def generate_user_report(user_ids)
    user_ids.each do |id|
      user = User.find(id)  # Database query in loop
      posts = user.posts    # Another query for each user
      puts "#{user.name}: #{posts.count} posts"
    end
  end

  # Bad: String concatenation in loop
  def build_csv(records)
    csv = ""
    records.each do |record|
      csv += "#{record.id},#{record.name}\n"  # String concatenation
    end
    csv
  end

  # Bad: Inefficient array search in nested loop
  def find_matches(list_a, list_b)
    matches = []
    list_a.each do |item_a|
      list_b.each do |item_b|
        matches << item_a if item_a == item_b
      end
    end
    matches
  end

  # Bad: Loading all records into memory
  def process_all_users
    User.all.each do |user|  # Should use find_each for batching
      send_email(user)
    end
  end
end

# Should be caught when priority is "performance" or "database queries"
