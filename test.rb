# Ruby file - should be skipped per custom instructions
class User
  def initialize(name)
    @name = name
  end

  # This has SQL injection but should be ignored (Ruby file)
  def find_user(id)
    query = "SELECT * FROM users WHERE id = #{id}"
    DB.execute(query)
  end

  # Bad code quality but should be ignored
  def bad_method
    x=1
    y=2
    z=3
    return x+y+z
  end
end
