require 'geokit'
require 'sun_times'
Geokit::default_units = :kms # TODO: use global settings

module Reality
  module Geo
    # Keeps information about coordinates point.
    # All services that are based on particular point in space (Weather, Time) depend on it.
    # Many Entity types can have coordinates, they can be accessed as #coord  method which returns this class.
    #
    # Example:
    #
    # ```ruby
    # Reality::Entity('Mississippi').coord
    # # => #<Reality::Geo::Coord(33°0′0″N,90°0′0″W)>
    # ```
    #
    # Usage examples:
    #
    # ```ruby
    # coord = Reality::Geo::Coord.new(50.45, 30.52)
    # # => #<Reality::Geo::Coord(50°27′0″N,30°31′24″E)>
    # coord.sunrise
    # #  => 2016-03-31 03:35:22 UTC
    # coord.distance_to(Reality::Entity('London'))
    # #  => #<Reality::Measure(2,135 km)>
    # ```
    #
    # Uses Geokit for some operations like #distance_to, #close_to? etc.
    #
    class Coord
      attr_reader :lat, :lng

      alias_method :latitude, :lat
      alias_method :longitude, :lng

      class << self
        def from_dms(lat, lng)
          new(decimal_from_dms(lat), decimal_from_dms(lng))
        end

        private

        DIRS = {
          'N' => +1,
          'S' => -1,
          'E' => +1,
          'W' => -1
        }

        def parse_direction(dir)
          DIRS[dir] or fail("Undefined coordinates direction: #{dir.inspect}")
        end

        def decimal_from_dms(dms)
          sign = if dms.last.is_a?(String)
            parse_direction(dms.pop)
          else
            dms.first.to_i <=> 0
          end
          
          d, m, s = *dms
          sign * (d.abs.to_i + Rational(m.to_i) / 60 + Rational(s.to_f) / 3600)
        end
      end

      # @param latitude
      # @param longitude
      def initialize(lat, lng)
        @lat, @lng = Rational(lat), Rational(lng)
      end

      # @param point - Coordinates, e.g "50.45,30.52", [50.45, 30.52], Coord or Entity instance
      #
      # @return [Reality::Measure]
      def distance_to(point)
        destination_coords = normalize_point(point).to_s
        res = Geokit::LatLng.distance_between(to_s, destination_coords, formula: :sphere)
        Reality::Measure(res, 'km')
      end

      # @param point - Coordinates, e.g "50.45,30.52", [50.45, 30.52], Coord or Entity instance
      #
      # @return [Reality::Measure]
      def direction_to(point)
        destination_coords = normalize_point(point).to_s
        res = Geokit::LatLng.heading_between(to_s, destination_coords)
        Reality::Measure(res, '°')
      end

      # @param direction - angle from the North by clock, e.g. '90' means 'to the east'
      # @param distance - km, e.g. 100
      #
      # @return [Reality::Geo::Coord]
      def endpoint(direction, distance)
        res = Geokit::LatLng.endpoint(to_s, direction.to_f, distance.to_f)
        Coord.new res.lat, res.lng
      end

      # @param point - Coordinates, e.g "50.45,30.52", [50.45, 30.52], Coord or Entity instance
      # @param radius - km, e.g. 10
      #
      # @return [true, false]
      def close_to?(point, radius)
        area = Geokit::Bounds.from_point_and_radius(to_s, radius.to_f)
        area.contains?(normalize_point(point).to_s)
      end

      # Latitude in "degrees minutes seconds" format
      #
      # @return [Array]
      def lat_dms(direction = true)
        seconds = (lat.abs % 1.0) * 3600.0
        d, m, s = lat.to_i, (seconds / 60).to_i, (seconds % 60)
        if direction
          [d.abs, m, s, d >= 0 ? 'N' : 'S']
        else
          [d, m, s]
        end
      end

      # Longitude in "degrees minutes seconds" format
      #
      # @return [Array]
      def lng_dms(direction = true)
        seconds = (lng.abs % 1.0) * 3600.0
        d, m, s = lng.to_i, (seconds / 60).to_i, (seconds % 60)
        if direction
          [d.abs, m, s, d >= 0 ? 'E' : 'W']
        else
          [d, m, s]
        end
      end

      def to_s
        "#{lat.to_f},#{lng.to_f}"
      end
      alias_method :latlng, :to_s

      def to_h
        {lat: lat.to_f, lng: lng.to_f}
      end

      def ==(other)
        other.is_a?(self.class) && lat == other.lat && lng == self.lng
      end

      def inspect
        "#<%s(%i°%i′%.0f″%s,%i°%i′%.0f″%s)>" % [self.class, *lat_dms, *lng_dms]
      end

      def sunrise(date = Date.today)
        SunTimes.new.rise(date, lat.to_f, lng.to_f)
      end

      def sunset(date = Date.today)
        SunTimes.new.set(date, lat.to_f, lng.to_f)
      end

      # Links to popular maps sites with this point marked
      # Maps: openstreetmap, google maps, wikimapia
      #
      # @return [Hash]
      def links
        param = {lat: lat.to_f, lng: lng.to_f, latlng: latlng}
        Hashie::Mash.new(EXTERNAL_LINKS.map{|key, pattern| [key, pattern % param]}.to_h)
      end

      private

      EXTERNAL_LINKS = {
        osm: "https://www.openstreetmap.org/?mlat=%{lat}&mlon=%{lng}&zoom=12&layers=M",
        google: "https://maps.google.com/maps?ll=%{latlng}&q=%{latlng}&hl=en&t=m&z=12",
        wikimapia: "http://wikimapia.org/#lang=en&lat=%{lat}&lon=%{lng}&z=12&m=w"
      }

      def normalize_point(point)
        return point if point.is_a?(Coord)
        point.coord if point.respond_to?(:coord)
      end
    end
  end
end
