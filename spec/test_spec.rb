require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  describe '#initialize' do
    context 'with a normal name string' do
      let(:name) { 'Alice' }
      let(:user) { described_class.new(name) }

      it 'creates a User instance' do
        expect(user).to be_a(described_class)
      end

      it 'sets @name to the provided value' do
        expect(user.instance_variable_get(:@name)).to eq(name)
      end
    end

    context 'with nil name' do
      let(:name) { nil }
      let(:user) { described_class.new(name) }

      it 'allows nil and stores it' do
        expect(user.instance_variable_get(:@name)).to be_nil
      end
    end

    context 'with empty string name' do
      let(:name) { '' }
      let(:user) { described_class.new(name) }

      it 'stores the empty string' do
        expect(user.instance_variable_get(:@name)).to eq('')
      end
    end
  end

  describe '#find_user' do
    let(:user) { described_class.new('Bob') }
    let(:db_double) { double('DB') }

    before do
      stub_const('DB', db_double)
    end

    context 'with integer id' do
      let(:id) { 42 }
      let(:query) { "SELECT * FROM users WHERE id = #{id}" }

      it 'calls DB.execute with the interpolated query and returns the result' do
        expected = [{ id: 42, name: 'Bob' }]
        expect(db_double).to receive(:execute).with(query).and_return(expected)
        result = user.find_user(id)
        expect(result).to eq(expected)
      end
    end

    context 'with string id' do
      let(:id) { '7' }
      let(:query) { "SELECT * FROM users WHERE id = #{id}" }

      it 'interpolates id as-is into the query' do
        expect(db_double).to receive(:execute).with(query).and_return('ok')
        expect(user.find_user(id)).to eq('ok')
      end
    end

    context 'with id containing SQL content' do
      let(:id) { '1; DROP TABLE users; --' }
      let(:query) { "SELECT * FROM users WHERE id = #{id}" }

      it 'passes the raw id through to the query' do
        expect(db_double).to receive(:execute).with(query).and_return('danger')
        expect(user.find_user(id)).to eq('danger')
      end
    end

    context 'with nil id' do
      let(:id) { nil }
      let(:query) { "SELECT * FROM users WHERE id = #{id}" }

      it 'interpolates nil into the query and returns DB response' do
        expect(db_double).to receive(:execute).with(query).and_return(nil)
        expect(user.find_user(id)).to be_nil
      end
    end

    context 'when DB.execute raises an error' do
      let(:id) { 1 }
      let(:query) { "SELECT * FROM users WHERE id = #{id}" }

      it 'propagates the error' do
        expect(db_double).to receive(:execute).with(query).and_raise(StandardError.new('DB error'))
        expect do
          user.find_user(id)
        end.to raise_error(StandardError, 'DB error')
      end
    end
  end

  describe '#bad_method' do
    let(:user) { described_class.new('Charlie') }

    it 'returns the sum of x, y, and z' do
      expect(user.bad_method).to eq(6)
    end

    it 'returns an Integer' do
      expect(user.bad_method).to be_a(Integer)
    end

    it 'is consistent across multiple calls and instances' do
      other = described_class.new('Dana')
      expect(user.bad_method).to eq(6)
      expect(other.bad_method).to eq(6)
    end
  end
end
