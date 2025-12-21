require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  describe '#initialize' do
    context 'with a non-empty name' do
      let(:name) { 'Alice' }
      let(:user) { described_class.new(name) }

      it 'sets the @name instance variable' do
        expect(user.instance_variable_get(:@name)).to eq('Alice')
      end
    end

    context 'with an empty string name' do
      let(:name) { '' }
      let(:user) { described_class.new(name) }

      it 'sets @name to empty string' do
        expect(user.instance_variable_get(:@name)).to eq('')
      end
    end

    context 'with a nil name' do
      let(:name) { nil }
      let(:user) { described_class.new(name) }

      it 'sets @name to nil' do
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end
  end

  describe '#find_user' do
    let(:user) { described_class.new('Any') }
    let(:db_double) { double('DB') }

    before do
      stub_const('DB', db_double)
    end

    context 'with an integer id' do
      let(:id) { 42 }
      let(:expected_query) { 'SELECT * FROM users WHERE id = 42' }
      let(:result_set) { [{ 'id' => 42, 'name' => 'Bob' }] }

      it 'calls DB.execute with interpolated SQL and returns its result' do
        expect(DB).to receive(:execute).with(expected_query).and_return(result_set)
        result = user.find_user(id)
        expect(result).to eq(result_set)
      end
    end

    context 'with a string id' do
      let(:id) { '7' }
      let(:expected_query) { 'SELECT * FROM users WHERE id = 7' }
      let(:result_set) { ['row'] }

      it 'interpolates the string id and returns the DB result' do
        expect(DB).to receive(:execute).with(expected_query).and_return(result_set)
        expect(user.find_user(id)).to eq(result_set)
      end
    end

    context 'with a malicious id string' do
      let(:id) { '1; DROP TABLE users;' }
      let(:expected_query) { 'SELECT * FROM users WHERE id = 1; DROP TABLE users;' }
      let(:result_set) { [] }

      it 'passes the unsanitized query to DB.execute' do
        expect(DB).to receive(:execute).with(expected_query).and_return(result_set)
        expect(user.find_user(id)).to eq(result_set)
      end
    end

    context 'with nil id' do
      let(:id) { nil }
      let(:expected_query) { 'SELECT * FROM users WHERE id = ' }
      let(:result_set) { nil }

      it 'interpolates nil as empty string and returns the DB result' do
        expect(DB).to receive(:execute).with(expected_query).and_return(result_set)
        expect(user.find_user(id)).to be_nil
      end
    end

    context 'when DB.execute raises an error' do
      let(:id) { 1 }

      it 'propagates the error' do
        allow(DB).to receive(:execute).and_raise(StandardError, 'db failure')
        expect do
          user.find_user(id)
        end.to raise_error(StandardError, 'db failure')
      end
    end
  end

  describe '#bad_method' do
    let(:user) { described_class.new('Zoe') }

    it 'returns the sum of x, y, and z as 6' do
      expect(user.bad_method).to eq(6)
    end

    it 'does not require external dependencies' do
      expect do
        user.bad_method
      end.not_to raise_error
    end
  end
end
