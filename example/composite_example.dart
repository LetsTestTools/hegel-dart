import 'package:hegeltest/hegeltest.dart';
import 'package:test/test.dart';

class Address {
  final String street;
  final String city;
  final String zip;

  Address(this.street, this.city, this.zip);

  @override
  String toString() => '$street, $city $zip';
}

class User {
  final String name;
  final int age;
  final String email;
  final Address address;

  User({
    required this.name,
    required this.age,
    required this.email,
    required this.address,
  });

  @override
  String toString() => 'User($name, $age, $email, $address)';
}

/// Example of composing a complex domain object generator using `Generator.composite`.
final addressGen = Generator.composite<Address>((tc) {
  final street = tc.draw(text(minSize: 5, maxSize: 50));
  final city = tc.draw(text(minSize: 2, maxSize: 20));
  final zip = tc.draw(fromRegex(r'[0-9]{5}'));
  return Address(street, city, zip);
});

final userGen = Generator.composite<User>((tc) {
  final name = tc.draw(text(minSize: 2, maxSize: 30));
  final age = tc.draw(integers(min: 0, max: 120));
  final email = tc.draw(emails());
  final address = tc.draw(addressGen);

  return User(name: name, age: age, email: email, address: address);
});

/// Example using `map` and `where`
final evenAges = integers(min: 0, max: 100).where((x) => x % 2 == 0);
final stringifiedEvens = evenAges.map((x) => x.toString());

void main() {
  hegelTest('generates valid user objects', (tc) {
    final user = tc.draw(userGen);

    expect(user.name.length, greaterThanOrEqualTo(2));
    expect(user.age, inInclusiveRange(0, 120));
    expect(user.email, contains('@'));
    expect(user.address.zip, matches(RegExp(r'^[0-9]{5}$')));
  });

  hegelTest('generates strings of even integers', (tc) {
    final s = tc.draw(stringifiedEvens);
    final i = int.parse(s);
    expect(i % 2, equals(0));
  });
}
