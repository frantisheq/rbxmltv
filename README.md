xmltv parser in ruby

Install ruby 2.0+

gem install nokogiri mechanize days_and_times ruby-progressbar file-utils

gem install roman-numerals nokogiri-happymapper unidecoder ruby-xz


git clone https://github.com/frantisheq/rbxmltv.git

cd rbxmltv

git clone https://github.com/frantisheq/rbxmltv-data.git



To generate a file named cz-sk+0100.xml for 7 days with +0100 timezone and cache being used:

./main.rb -d 7 -t +0100 -o ./rbxmltv-data/cz-sk+0100.xml -c ./rbxmltv-data/cache


Timezone argument will be appended to xmltv channel id. Default value is set to +0100.

Use ./main.rb -h for help.
