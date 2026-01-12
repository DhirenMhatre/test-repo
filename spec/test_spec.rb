require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  let(:name) { 'Alice' }
  let(:user) { described_class.new(name) }

  describe '#initialize' do
    it 'creates a User instance' do
      expect(user).to be_a(described_class)
    end

    it 'does not raise an error when initialized with a name' do
      expect do
        described_class.new('Bob')
      end.not_to raise_error
    end

    it 'allows initialization with nil name' do
      expect do
        described_class.new(nil)
      end.not_to raise_error
    end
  end

  describe '#find_user' do
    let(:db_double) { class_double('DB') }

    before do
      stub_const('DB', db_double)
    end

    context 'with a valid integer id' do
      let(:id) { 1 }
      let(:query) { "SELECT * FROM users WHERE id = #{id}" }
      let(:result) { [{ 'id' => 1, 'name' => 'Alice' }] }

      it 'executes the expected SQL query' do
        expect(DB).to receive(:execute).with(query).and_return(result)
        user.find_user(id)
      end

      it 'returns the result from DB.execute' do
        allow(DB).to receive(:execute).with(query).and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'with a string id' do
      let(:id) { '2' }
      let(:query) { "SELECT * FROM users WHERE id = #{id}" }
      let(:result) { [{ 'id' => 2, 'name' => 'Bob' }] }

      it 'passes the interpolated id directly into the SQL query' do
        expect(DB).to receive(:execute).with(query).and_return(result)
        user.find_user(id)
      end
    end

    context 'with a nil id' do
      let(:id) { nil }
      let(:query) { "SELECT * FROM users WHERE id = #{id}" }

      it 'still builds and executes the query with nil' do
        expect(DB).to receive(:execute).with(query)
        user.find_user(id)
      end
    end

    context 'when DB.execute raises an error' do
      let(:id) { 3 }
      let(:query) { "SELECT * FROM users WHERE id = #{id}" }

      it 'propagates the error' do
        allow(DB).to receive(:execute).with(query).and_raise(StandardError.new('DB failure'))

        expect do
          user.find_user(id)
        end.to raise_error(StandardError, 'DB failure')
      end
    end
  end

  describe '#bad_method' do
    it 'returns the sum of internal variables' do
      expect(user.bad_method).to eq(6)
    end

    it 'always returns 6 regardless of name' do
      other_user = described_class.new('Different')
      expect(other_user.bad_method).to eq(6)
    end
  end
end
