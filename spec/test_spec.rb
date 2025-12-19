require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  let(:name) { 'Alice' }
  let(:user) { described_class.new(name) }

  describe '#initialize' do
    context 'with a valid name' do
      it 'sets @name to the provided name' do
        expect(user.instance_variable_get(:@name)).to eq('Alice')
      end
    end

    context 'with nil name' do
      let(:name) { nil }

      it 'sets @name to nil' do
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end
  end

  describe '#find_user' do
    let(:db) { double('DB') }

    before do
      stub_const('DB', db)
    end

    context 'when id is an integer' do
      let(:id) { 42 }
      let(:expected_query) { 'SELECT * FROM users WHERE id = 42' }
      let(:db_result) { [{ 'id' => 42, 'name' => 'Alice' }] }

      it 'calls DB.execute with the correct SQL and returns the result' do
        expect(DB).to receive(:execute).with(expected_query).once.and_return(db_result)
        result = user.find_user(id)
        expect(result).to eq(db_result)
      end
    end

    context 'when id is nil' do
      let(:id) { nil }
      let(:expected_query) { 'SELECT * FROM users WHERE id = ' }
      let(:db_result) { [] }

      it 'calls DB.execute with an empty id string and returns the result' do
        expect(DB).to receive(:execute).with(expected_query).and_return(db_result)
        result = user.find_user(id)
        expect(result).to eq(db_result)
      end
    end

    context 'when id contains SQL special characters' do
      let(:id) { '1; DROP TABLE users; --' }
      let(:expected_query) { 'SELECT * FROM users WHERE id = 1; DROP TABLE users; --' }
      let(:db_result) { ['unsafe'] }

      it 'passes the unsanitized id directly to the SQL string and returns the result' do
        expect(DB).to receive(:execute).with(expected_query).and_return(db_result)
        result = user.find_user(id)
        expect(result).to eq(db_result)
      end
    end

    context 'when DB.execute raises an error' do
      let(:id) { 1 }

      it 'propagates the error' do
        allow(DB).to receive(:execute).and_raise(StandardError.new('boom'))
        expect { user.find_user(id) }.to raise_error(StandardError, 'boom')
      end
    end
  end

  describe '#bad_method' do
    it 'returns the sum of 1, 2, and 3' do
      expect(user.bad_method).to eq(6)
    end

    it 'returns an Integer' do
      expect(user.bad_method).to be_a(Integer)
    end
  end
end
