require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  let(:name) { 'Alice' }
  let(:user) { described_class.new(name) }

  describe '#initialize' do
    it 'creates a User instance with the given name' do
      expect(user).to be_a(described_class)
    end

    context 'when name is nil' do
      let(:name) { nil }

      it 'creates a User instance even with nil name' do
        expect(user).to be_a(described_class)
      end
    end

    context 'when name is an empty string' do
      let(:name) { '' }

      it 'creates a User instance with empty name' do
        expect(user).to be_a(described_class)
      end
    end
  end

  describe '#find_user' do
    let(:db_double) { class_double('DB') }
    let(:id) { 1 }
    let(:query) { "SELECT * FROM users WHERE id = #{id}" }
    let(:result) { [{ 'id' => id, 'name' => name }] }

    before do
      stub_const('DB', db_double)
    end

    context 'with a valid integer id' do
      it 'executes the correct SQL query and returns the result' do
        expect(DB).to receive(:execute).with(query).and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'with a string id' do
      let(:id) { '2' }
      let(:query) { "SELECT * FROM users WHERE id = #{id}" }

      it 'passes the interpolated id directly into the query' do
        expect(DB).to receive(:execute).with(query).and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'with a nil id' do
      let(:id) { nil }
      let(:query) { "SELECT * FROM users WHERE id = #{id}" }

      it 'builds a query with nil and executes it' do
        expect(DB).to receive(:execute).with(query).and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'when DB.execute raises an error' do
      let(:db_error) { StandardError.new('DB failure') }

      it 'propagates the error' do
        expect(DB).to receive(:execute).with(query).and_raise(db_error)
        expect do
          user.find_user(id)
        end.to raise_error(StandardError, 'DB failure')
      end
    end
  end

  describe '#bad_method' do
    it 'returns the sum of x, y, and z' do
      expect(user.bad_method).to eq(6)
    end

    context 'called multiple times' do
      it 'returns the same result each time' do
        first = user.bad_method
        second = user.bad_method
        expect(first).to eq(6)
        expect(second).to eq(6)
      end
    end
  end
end
