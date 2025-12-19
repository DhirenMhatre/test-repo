require 'spec_helper'
require_relative '../test'

RSpec.describe User do
  describe '#initialize' do
    context 'with a valid name' do
      let(:name) { 'Alice' }
      let(:user) { described_class.new(name) }

      it 'sets the @name instance variable' do
        expect(user.instance_variable_get(:@name)).to eq(name)
      end
    end

    context 'with an empty name' do
      let(:user) { described_class.new('') }

      it 'allows an empty name' do
        expect(user.instance_variable_get(:@name)).to eq('')
      end
    end
  end

  describe '#find_user' do
    let(:user) { described_class.new('tester') }

    context 'with an integer id' do
      let(:id) { 123 }
      let(:result) { [{ 'id' => 123, 'name' => 'Bob' }] }

      it 'calls DB.execute with the interpolated id and returns the DB result' do
        query = "SELECT * FROM users WHERE id = #{id}"
        stub_const('DB', double('DB'))
        expect(DB).to receive(:execute).with(query).and_return(result)
        expect(user.find_user(id)).to eq(result)
      end
    end

    context 'with a string id that could inject SQL' do
      let(:id) { '1; DROP TABLE users; --' }

      it 'passes the raw string into the query interpolation (unsafe)' do
        query = "SELECT * FROM users WHERE id = #{id}"
        stub_const('DB', double('DB'))
        expect(DB).to receive(:execute).with(query).and_return(:ok)
        expect(user.find_user(id)).to eq(:ok)
      end
    end

    context 'with nil id' do
      let(:id) { nil }

      it 'builds a query with empty interpolation and calls DB' do
        query = 'SELECT * FROM users WHERE id = '
        stub_const('DB', double('DB'))
        expect(DB).to receive(:execute).with(query).and_return(nil)
        expect(user.find_user(id)).to be_nil
      end
    end

    context 'when DB.execute raises an error' do
      let(:id) { 1 }

      it 'propagates the error' do
        query = "SELECT * FROM users WHERE id = #{id}"
        stub_const('DB', double('DB'))
        allow(DB).to receive(:execute).with(query).and_raise(StandardError, 'db failure')
        expect do
          user.find_user(id)
        end.to raise_error(StandardError, 'db failure')
      end
    end
  end

  describe '#bad_method' do
    let(:user) { described_class.new('tester') }

    it 'returns the sum of internal variables' do
      expect(user.bad_method).to eq(6)
    end
  end
end
