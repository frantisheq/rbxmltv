xmltv parser in ruby

install ruby 2.0+

gem install nokogiri mechanize days_and_times ruby-progressbar file-utils
gem install roman-numerals nokogiri-happymapper unidecoder ruby-xz


git clone https://github.com/frantisheq/rbxmltv.git
cd rbxmltv
git clone https://github.com/frantisheq/rbxmltv-data.git

./main.rb -d 7 -o ./rbxmltv-data/cz-sk.xml -c ./rbxmltv-data/cache

