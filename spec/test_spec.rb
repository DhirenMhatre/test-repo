require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  let(:name) { 'Alice' }
  let(:user) { described_class.new(name) }
  let(:db) { double('DB') }
  let!(:stub_db) do
    stub_const('DB', db)
  end

  describe '#initialize' do
    context 'with a valid name' do
      it 'sets the @name instance variable' do
        instance = described_class.new('Bob')
        expect(instance.instance_variable_get(:@name)).to eq('Bob')
      end
    end

    context 'with an empty string name' do
      it 'sets @name to empty string' do
        instance = described_class.new('')
        expect(instance.instance_variable_get(:@name)).to eq('')
      end
    end

    context 'with nil name' do
      it 'sets @name to nil' do
        instance = described_class.new(nil)
        expect(instance.instance_variable_get(:@name)).to be_nil
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
    context 'when id is an integer' do
      it 'calls DB.execute with the correct query and returns its result' do
        expect(db).to receive(:execute).with('SELECT * FROM users WHERE id = 42').and_return(:row)
        result = user.find_user(42)
        expect(result).to eq(:row)
      end
    end

    context 'when id is a numeric string' do
      it 'interpolates the string id directly into the SQL without quotes' do
        expect(db).to receive(:execute).with('SELECT * FROM users WHERE id = 7').and_return(:row7)
        result = user.find_user('7')
        expect(result).to eq(:row7)
      end
    end

    context 'when id is nil' do
      it 'builds a query with an empty id and returns nil from DB' do
        expect(db).to receive(:execute).with('SELECT * FROM users WHERE id = ').and_return(nil)
        result = user.find_user(nil)
        expect(result).to be_nil
      end
    end

    context 'when id contains SQL injection content' do
      let(:malicious_id) { '1; DROP TABLE users; --' }

      it 'passes the raw interpolated string to DB.execute' do
        expected_query = 'SELECT * FROM users WHERE id = 1; DROP TABLE users; --'
        expect(db).to receive(:execute).with(expected_query).and_return(:rows)
        result = user.find_user(malicious_id)
        expect(result).to eq(:rows)
      end
    end

    context 'when DB.execute raises an error' do
      it 'propagates the error' do
        expect(db).to receive(:execute).with('SELECT * FROM users WHERE id = 5').and_raise(StandardError, 'db failure')
        expect do
          user.find_user(5)
        end.to raise_error(StandardError, 'db failure')
      end
    end
  end

  describe '#bad_method' do
    it 'returns the sum of internal variables' do
      expect(user.bad_method).to eq(6)
    end

    it 'does not depend on @name value' do
      instance = described_class.new('Different Name')
      expect(instance.bad_method).to eq(6)
    end
  end
end
