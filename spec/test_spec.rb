require 'spec_helper'

RSpec.describe User do
  describe '#initialize' do
    let(:name) { 'Alice' }
    let(:user) { described_class.new(name) }

    context 'with a normal name' do
      it 'sets the @name instance variable' do
        expect(user.instance_variable_get(:@name)).to eq('Alice')
      end
    end

    context 'with nil name' do
      let(:name) { nil }

      it 'sets @name to nil' do
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end

    context 'with empty string name' do
      let(:name) { '' }

      it 'sets @name to an empty string' do
        expect(user.instance_variable_get(:@name)).to eq('')
      end
    end
  end

  describe '#find_user' do
    let(:user) { described_class.new('any') }
    let(:db) { double('DB') }

    before do
      stub_const('DB', db)
    end

    context 'when id is an integer and DB succeeds' do
      let(:id) { 42 }
      let(:expected_query) { "SELECT * FROM users WHERE id = #{id}" }
      let(:db_result) { [{ 'id' => 42, 'name' => 'Bob' }] }

      it 'executes the expected SQL and returns the DB result' do
        expect(db).to receive(:execute).with(expected_query).and_return(db_result)
        result = user.find_user(id)
        expect(result).to eq(db_result)
      end
    end

    context 'when id is a string that could be unsafe' do
      let(:id) { '1 OR 1=1' }
      let(:expected_query) { "SELECT * FROM users WHERE id = #{id}" }
      let(:db_result) { [] }

      it 'passes the raw interpolated id to the SQL query' do
        expect(db).to receive(:execute).with(expected_query).and_return(db_result)
        result = user.find_user(id)
        expect(result).to eq(db_result)
      end
    end

    context 'when id is nil' do
      let(:id) { nil }
      let(:expected_query) { 'SELECT * FROM users WHERE id = ' }
      let(:db_result) { nil }

      it 'interpolates nil as empty string and calls DB.execute' do
        expect(db).to receive(:execute).with(expected_query).and_return(db_result)
        result = user.find_user(id)
        expect(result).to be_nil
      end
    end

    context 'when DB raises an error' do
      let(:id) { 1 }
      let(:expected_query) { "SELECT * FROM users WHERE id = #{id}" }

      it 'propagates the error' do
        expect(db).to receive(:execute).with(expected_query).and_raise(StandardError, 'db error')
        expect { user.find_user(id) }.to raise_error(StandardError, 'db error')
      end
    end
  end

  describe '#bad_method' do
    let(:user) { described_class.new('Alice') }

    it 'returns the sum of internal variables (6)' do
      expect(user.bad_method).to eq(6)
    end

    it 'returns an Integer' do
      expect(user.bad_method).to be_a(Integer)
    end

    context 'regardless of the name provided' do
      let(:user) { described_class.new(nil) }

      it 'still returns 6' do
        expect(user.bad_method).to eq(6)
      end
    end
  end
end
