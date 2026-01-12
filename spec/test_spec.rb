require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  let(:name) { 'Alice' }
  let(:user) { described_class.new(name) }

  describe '#initialize' do
    it 'sets the name instance variable' do
      expect(user.instance_variable_get(:@name)).to eq(name)
    end

    context 'with nil name' do
      let(:name) { nil }

      it 'allows nil as name' do
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end

    context 'with empty string name' do
      let(:name) { '' }

      it 'sets an empty string as name' do
        expect(user.instance_variable_get(:@name)).to eq('')
      end
    end
  end

  describe '#find_user' do
    let(:db_double) { class_double('DB') }
    let(:id) { 1 }
    let(:query) { "SELECT * FROM users WHERE id = #{id}" }
    let(:result) { [{ id: id, name: 'Alice' }] }

    before do
      stub_const('DB', db_double)
    end

    context 'with a valid integer id' do
      it 'executes the expected SQL query on DB and returns the result' do
        expect(DB).to receive(:execute).with(query).and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'with a string id' do
      let(:id) { '2' }
      let(:query) { "SELECT * FROM users WHERE id = #{id}" }

      it 'interpolates the string id into the SQL query' do
        expect(DB).to receive(:execute).with(query).and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'with a nil id' do
      let(:id) { nil }
      let(:query) { "SELECT * FROM users WHERE id = #{id}" }

      it 'builds a query including nil and passes it to DB' do
        expect(DB).to receive(:execute).with(query).and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'when DB raises an error' do
      let(:db_error) { StandardError.new('DB failure') }

      it 'propagates the error' do
        expect(DB).to receive(:execute).with(query).and_raise(db_error)
        expect do
          user.find_user(id)
        end.to raise_error(StandardError, 'DB failure')
      end
    end

    context 'when DB returns nil' do
      it 'returns nil' do
        expect(DB).to receive(:execute).with(query).and_return(nil)
        expect(user.find_user(id)).to be_nil
      end
    end

    context 'when DB returns an empty array' do
      it 'returns the empty array' do
        expect(DB).to receive(:execute).with(query).and_return([])
        expect(user.find_user(id)).to eq([])
      end
    end
  end

  describe '#bad_method' do
    it 'returns the sum of x, y, and z' do
      expect(user.bad_method).to eq(6)
    end

    it 'always returns an Integer' do
      expect(user.bad_method).to be_a(Integer)
    end

    context 'multiple calls' do
      it 'is deterministic across calls' do
        first = user.bad_method
        second = user.bad_method
        expect(first).to eq(6)
        expect(second).to eq(6)
      end
    end
  end
end
