MongoMapper.connection = Mongo::Connection.new('staff.mongohq.com', 10007)
MongoMapper.database = 'twilio-sxsw'
MongoMapper.database.authenticate('twilio','twilioscales')

class User
  include MongoMapper::Document
  key :number, String
  key :on, Boolean

  timestamps!
end
