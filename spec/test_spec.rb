require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  describe '#initialize' do
    let(:name) { 'Alice' }
    let(:user) { described_class.new(name) }

    context 'with a valid name' do
      it 'sets the @name instance variable' do
        expect(user.instance_variable_get(:@name)).to eq('Alice')
      end
    end

    context 'with nil name' do
      let(:name) { nil }

      it 'allows nil and sets @name to nil' do
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end
  end

  describe '#find_user' do
    let(:db) { instance_double('DB') }
    let(:user) { described_class.new('Bob') }

    before do
      stub_const('DB', db)
    end

    context 'with an integer id' do
      let(:id) { 42 }

      it 'executes the expected SQL and returns the DB result' do
        expected_query = 'SELECT * FROM users WHERE id = 42'
        expected_result = [{ 'id' => 42 }]
        expect(db).to receive(:execute).with(expected_query).and_return(expected_result)
        result = user.find_user(id)
        expect(result).to eq(expected_result)
      end
    end

    context 'with a string id (potential SQL injection)' do
      let(:id) { '1; DROP TABLE users;' }

      it 'passes the interpolated id directly into the SQL' do
        expected_query = 'SELECT * FROM users WHERE id = 1; DROP TABLE users;'
        expect(db).to receive(:execute).with(expected_query).and_return('ok')
        expect(user.find_user(id)).to eq('ok')
      end
    end

    context 'with nil id' do
      let(:id) { nil }

      it 'builds the SQL with an empty id and returns the DB result' do
        expected_query = 'SELECT * FROM users WHERE id = '
        expect(db).to receive(:execute).with(expected_query).and_return([])
        expect(user.find_user(id)).to eq([])
      end
    end

    context 'when DB raises an error' do
      it 'propagates the error' do
        expect(db).to receive(:execute).and_raise(RuntimeError, 'DB error')
        expect { user.find_user(5) }.to raise_error(RuntimeError, 'DB error')
      end
    end
  end

  describe '#bad_method' do
    let(:user) { described_class.new('Charlie') }

    it 'returns the sum of internal values' do
      expect(user.bad_method).to eq(6)
    end

    it 'does not raise an error' do
      expect { user.bad_method }.not_to raise_error
    end
  end
end
