require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  describe '#initialize' do
    it 'sets the @name instance variable' do
      user = described_class.new('Alice')
      expect(user.instance_variable_get(:@name)).to eq('Alice')
    end
  end

  describe '#find_user' do
    let(:user) { described_class.new('Alice') }
    let(:db_double) { double('DB') }

    before do
      stub_const('DB', db_double)
    end

    context 'with an integer id' do
      let(:id) { 42 }
      let(:result) { [{ id: 42, name: 'Bob' }] }

      it 'executes the correct SQL and returns the DB result' do
        expect(DB).to receive(:execute).with('SELECT * FROM users WHERE id = 42').and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'when DB returns nil' do
      it 'returns nil' do
        expect(DB).to receive(:execute).with('SELECT * FROM users WHERE id = 0').and_return(nil)
        expect(user.find_user(0)).to be_nil
      end
    end

    context 'with a string id (potential SQL injection)' do
      it 'passes the raw id into the SQL string' do
        dangerous_id = '1; DROP TABLE users; --'
        expected_query = 'SELECT * FROM users WHERE id = 1; DROP TABLE users; --'
        expect(DB).to receive(:execute).with(expected_query).and_return(:ok)
        expect(user.find_user(dangerous_id)).to eq(:ok)
      end
    end

    context 'with nil id' do
      it 'builds a query with an empty id and returns the DB result' do
        expected_query = 'SELECT * FROM users WHERE id = '
        expect(DB).to receive(:execute).with(expected_query).and_return([])
        expect(user.find_user(nil)).to eq([])
      end
    end

    context 'when DB.execute raises an error' do
      it 'propagates the error' do
        expect(DB).to receive(:execute).with('SELECT * FROM users WHERE id = 7').and_raise(StandardError.new('db error'))
        expect do
          user.find_user(7)
        end.to raise_error(StandardError, 'db error')
      end
    end
  end

  describe '#bad_method' do
    let(:user) { described_class.new('Alice') }

    it 'returns the sum of internal variables' do
      expect(user.bad_method).to eq(6)
    end

    it 'returns an Integer' do
      expect(user.bad_method).to be_a(Integer)
    end
  end
end
