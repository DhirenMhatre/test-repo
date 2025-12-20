require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  describe '#initialize' do
    context 'with a valid name' do
      let(:name) do
        'Alice'
      end

      let(:user) do
        described_class.new(name)
      end

      it 'stores the provided name in @name' do
        expect(user.instance_variable_get(:@name)).to eq('Alice')
      end
    end

    context 'with nil name' do
      it 'stores nil in @name' do
        user = described_class.new(nil)
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end

    context 'with missing argument' do
      it 'raises ArgumentError' do
        expect do
          described_class.new
        end.to raise_error(ArgumentError)
      end
    end
  end

  describe '#find_user' do
    let(:user) do
      described_class.new('any')
    end

    let(:db) do
      double('DB')
    end

    before do
      stub_const('DB', db)
    end

    context 'when id is an integer' do
      let(:id) do
        1
      end

      it 'executes the expected SQL and returns the DB result' do
        expected_query = "SELECT * FROM users WHERE id = #{id}"
        db_result = 'db-result'
        expect(db).to receive(:execute).with(expected_query).and_return(db_result)
        result = user.find_user(id)
        expect(result).to eq(db_result)
      end
    end

    context 'when id is a string (potentially unsafe input)' do
      let(:id) do
        '1 OR 1=1; --'
      end

      it 'passes the interpolated SQL directly to DB.execute' do
        expected_query = "SELECT * FROM users WHERE id = #{id}"
        db_result = 'db-result-2'
        expect(db).to receive(:execute).with(expected_query).and_return(db_result)
        result = user.find_user(id)
        expect(result).to eq(db_result)
      end
    end

    context 'when id is nil' do
      let(:id) do
        nil
      end

      it 'builds a SQL query with an empty interpolation and returns the DB result' do
        expected_query = 'SELECT * FROM users WHERE id = '
        db_result = 'nil-result'
        expect(db).to receive(:execute).with(expected_query).and_return(db_result)
        result = user.find_user(id)
        expect(result).to eq(db_result)
      end
    end

    context 'when DB.execute raises an error' do
      let(:id) do
        99
      end

      it 'propagates the error' do
        expected_query = "SELECT * FROM users WHERE id = #{id}"
        expect(db).to receive(:execute).with(expected_query).and_raise(StandardError.new('DB failure'))
        expect do
          user.find_user(id)
        end.to raise_error(StandardError, 'DB failure')
      end
    end
  end

  describe '#bad_method' do
    let(:user) do
      described_class.new('Bob')
    end

    it 'returns the sum of its internal variables' do
      expect(user.bad_method).to eq(6)
    end

    it 'returns an Integer' do
      expect(user.bad_method).to be_a(Integer)
    end
  end
end
