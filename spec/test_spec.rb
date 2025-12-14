require 'spec_helper'

RSpec.describe User do
  describe '#initialize' do
    context 'with a name' do
      let(:name) { 'Alice' }
      let(:user) { described_class.new(name) }

      it 'sets @name to the provided value' do
        expect(user.instance_variable_get(:@name)).to eq('Alice')
      end
    end

    context 'with nil name' do
      let(:name) { nil }
      let(:user) { described_class.new(name) }

      it 'sets @name to nil' do
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end

    context 'without required argument' do
      it 'raises ArgumentError' do
        expect do
          described_class.new
        end.to raise_error(ArgumentError)
      end
    end
  end

  describe '#find_user' do
    let(:name) { 'Alice' }
    let(:user) { described_class.new(name) }
    let(:db) { double('DB') }

    before do
      stub_const('DB', db)
    end

    context 'with integer id' do
      let(:id) { 42 }
      let(:db_result) { [{ 'id' => 42, 'name' => 'Bob' }] }

      it 'executes the expected SQL and returns the DB result' do
        expected_query = 'SELECT * FROM users WHERE id = 42'
        expect(db).to receive(:execute).with(expected_query).and_return(db_result)
        result = user.find_user(id)
        expect(result).to eq(db_result)
      end
    end

    context 'with string id containing SQL characters' do
      let(:id) { '1; DROP TABLE users;' }
      let(:db_result) { 'ok' }

      it 'interpolates the id directly into the SQL string' do
        expected_query = 'SELECT * FROM users WHERE id = 1; DROP TABLE users;'
        expect(db).to receive(:execute).with(expected_query).and_return(db_result)
        result = user.find_user(id)
        expect(result).to eq(db_result)
      end
    end

    context 'with nil id' do
      let(:id) { nil }
      let(:db_result) { [] }

      it 'calls DB.execute with a query containing an empty id and returns the result' do
        expected_query = 'SELECT * FROM users WHERE id = '
        expect(db).to receive(:execute).with(expected_query).and_return(db_result)
        result = user.find_user(id)
        expect(result).to eq(db_result)
      end
    end

    context 'when DB.execute raises an error' do
      let(:id) { 7 }

      it 'propagates the error' do
        expected_query = 'SELECT * FROM users WHERE id = 7'
        expect(db).to receive(:execute).with(expected_query).and_raise(StandardError, 'DB failure')
        expect do
          user.find_user(id)
        end.to raise_error(StandardError, 'DB failure')
      end
    end
  end

  describe '#bad_method' do
    let(:name) { 'Alice' }
    let(:user) { described_class.new(name) }

    it 'returns the sum of internal values' do
      expect(user.bad_method).to eq(6)
    end

    it 'returns an Integer' do
      expect(user.bad_method).to be_a(Integer)
    end
  end
end
