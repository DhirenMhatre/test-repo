require 'spec_helper'

RSpec.describe User do
  describe '#initialize' do
    context 'with a valid name' do
      let(:name) do
        'Alice'
      end

      it 'sets the @name instance variable' do
        user = described_class.new(name)
        expect(user.instance_variable_get(:@name)).to eq('Alice')
      end
    end

    context 'without a name' do
      it 'raises ArgumentError' do
        expect do
          described_class.new
        end.to raise_error(ArgumentError)
      end
    end
  end

  describe '#find_user' do
    let(:name) do
      'Bob'
    end

    let(:user) do
      described_class.new(name)
    end

    before do
      stub_const('DB', double('DB'))
    end

    context 'when DB returns a result' do
      let(:id) do
        1
      end

      let(:row) do
        { 'id' => 1, 'name' => 'Bob' }
      end

      it 'executes the expected SQL and returns the result' do
        expected_query = "SELECT * FROM users WHERE id = #{id}"
        expect(DB).to receive(:execute).with(expected_query).and_return(row)
        expect(user.find_user(id)).to eq(row)
      end
    end

    context 'when DB returns no result' do
      let(:id) do
        999
      end

      it 'returns nil when DB returns nil' do
        expected_query = "SELECT * FROM users WHERE id = #{id}"
        expect(DB).to receive(:execute).with(expected_query).and_return(nil)
        expect(user.find_user(id)).to be_nil
      end

      it 'returns an empty array when DB returns an empty array' do
        expected_query = "SELECT * FROM users WHERE id = #{id}"
        expect(DB).to receive(:execute).with(expected_query).and_return([])
        expect(user.find_user(id)).to eq([])
      end
    end

    context 'when id is nil' do
      it 'passes a query with nil interpolated and returns the DB value' do
        expected_query = 'SELECT * FROM users WHERE id = '
        expect(DB).to receive(:execute).with(expected_query).and_return('result')
        expect(user.find_user(nil)).to eq('result')
      end
    end

    context 'when id contains potentially malicious SQL' do
      it 'interpolates id directly into the query and sends it to DB' do
        malicious = '1; DROP TABLE users;--'
        expected_query = "SELECT * FROM users WHERE id = #{malicious}"
        expect(DB).to receive(:execute).with(expected_query).and_return('ok')
        expect(user.find_user(malicious)).to eq('ok')
      end
    end

    context 'when DB raises an error' do
      it 'propagates the error' do
        id = 2
        expected_query = "SELECT * FROM users WHERE id = #{id}"
        expect(DB).to receive(:execute).with(expected_query).and_raise(StandardError.new('db down'))
        expect do
          user.find_user(id)
        end.to raise_error(StandardError, 'db down')
      end
    end
  end

  describe '#bad_method' do
    let(:user) do
      described_class.new('Eve')
    end

    it 'returns the sum of x, y, and z' do
      expect(user.bad_method).to eq(6)
    end

    it 'returns an Integer' do
      expect(user.bad_method).to be_a(Integer)
    end

    it 'returns the same result across multiple calls' do
      first = user.bad_method
      second = user.bad_method
      expect(second).to eq(first)
    end
  end
end
