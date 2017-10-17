struct Lens<Whole,Part> {
	let get: (Whole) -> Part
	let set: (Part) -> (Whole) -> Whole
}

extension Lens {
	func over(_ transform: @escaping (Part) -> Part) -> (Whole) -> Whole {
		return { whole in self.set(transform(self.get(whole)))(whole) }
	}
	
	func compose<Subpart>(_ other: Lens<Part,Subpart>) -> Lens<Whole,Subpart> {
		return Lens<Whole,Subpart>(
			get: { other.get(self.get($0)) },
			set: { (subpart: Subpart) in
				{ (whole: Whole) -> Whole in
					self.set(other.set(subpart)(self.get(whole)))(whole)
				}
		})
	}
	
	static func zip<Part1,Part2>(
		_ a: Lens<Whole,Part1>,
		_ b: Lens<Whole,Part2>)
		-> Lens<Whole,(Part1,Part2)>
		where Part == (Part1,Part2)
	{
		return Lens<Whole,(Part1,Part2)>(
			get: { (a.get($0),b.get($0)) },
			set: { parts in { whole in b.set(parts.1)(a.set(parts.0)(whole)) } })
	}
	
	static func zip<A,B,C>(_ a: Lens<Whole,A>, _ b: Lens<Whole,B>, _ c: Lens<Whole,C>) -> Lens<Whole,(A,B,C)> where Part == (A,B,C) {
		return Lens<Whole,(A,B,C)>(
			get: { (a.get($0),b.get($0),c.get($0)) },
			set: { parts in { whole in c.set(parts.2)(b.set(parts.1)(a.set(parts.0)(whole))) } })
	}
}

struct Prism<Whole,Part> {
	let tryGet: (Whole) -> Part?
	let inject: (Part) -> Whole
}

enum Either<A,B> {
	case left(A)
	case right(B)
}

extension Prism {
	func tryOver(_ transform: @escaping (Part) -> Part) -> (Whole) -> Whole {
		return { whole in self.tryGet(whole).map { self.inject(transform($0)) } ?? whole }
	}
	
	func compose<Subpart>(_ other: Prism<Part,Subpart>) -> Prism<Whole,Subpart> {
		return Prism<Whole,Subpart>(
			tryGet: { self.tryGet($0).flatMap(other.tryGet) },
			inject: { self.inject(other.inject($0)) })
	}

	static func zip<Part1,Part2>(
		_ a: Prism<Whole,Part1>,
		_ b: Prism<Whole,Part2>)
		-> Prism<Whole,Either<Part1,Part2>>
		where Part == Either<Part1,Part2>
	{
		return Prism<Whole,Either<Part1,Part2>>(
			tryGet: { a.tryGet($0).map(Either.left) ?? b.tryGet($0).map(Either.right) },
			inject: { part in
				switch part {
				case .left(let value):
					return a.inject(value)
				case .right(let value):
					return b.inject(value)
				}
		})
	}
}

enum ViewState<T> {
	case empty
	case processing(String)
	case failed(Error)
	case completed(T)
}

struct LoginPage {
	var title: String
	var credentials: CredentialBox
	var buttonState: ViewState<Button>
}

struct CredentialBox {
	var usernameField: TextField
	var passwordField: TextField
}

struct TextField {
	var text: String
	var placeholder: String?
	var secureText: Bool
}

struct Button {
	var title: String
	var enabled: Bool
}

extension CredentialBox {
	enum lens {
		static let usernameField = Lens<CredentialBox,TextField>.init(
			get: { $0.usernameField },
			set: { part in
				{ whole in
					var m = whole
					m.usernameField = part
					return m
				}
		})
	}
}

extension ViewState {
	enum prism {
		static var processing: Prism<ViewState,String> {
			return .init(
				tryGet: {
					guard case .processing(let message) = $0 else {
						return nil
					}
					return message
				},
				inject: { .processing($0) })
		}
	}
}

let savedUsername = "foobar"

let oldModel = LoginPage.init(title: "", credentials: CredentialBox.init(usernameField: TextField.init(text: "", placeholder: nil, secureText: false), passwordField: TextField.init(text: "", placeholder: nil, secureText: true)), buttonState: .completed(Button.init(title: "", enabled: false)))

let initialState = (
	title: "Welcome back!",
	username: savedUsername,
	buttonState: ViewState<Button>.completed(Button.init(
		title: "Login",
		enabled: false)))

var m_newModel = oldModel
m_newModel.title = initialState.title
m_newModel.credentials.usernameField.text = initialState.username
m_newModel.buttonState = initialState.buttonState

extension LoginPage {
	enum lens {
		static let title = Lens<LoginPage,String>.init(
			get: { $0.title },
			set: { part in { var m = $0; m.title = part; return m }})
		
		static let credentials = Lens<LoginPage,CredentialBox>.init(
			get: { $0.credentials },
			set: { part in { var m = $0; m.credentials = part; return m }})
		
		static let buttonState = Lens<LoginPage,ViewState<Button>>.init(
			get: { $0.buttonState },
			set: { part in { var m = $0; m.buttonState = part; return m }})
	}
}

extension TextField {
	enum lens {
		static let text = Lens<TextField,String>.init(
			get: { $0.text },
			set: { part in { var m = $0; m.text = part; return m }})
	}
}

let titleLens = LoginPage.lens.title
let usernameTextLens = LoginPage.lens.credentials
	.compose(CredentialBox.lens.usernameField)
	.compose(TextField.lens.text)
let buttonStateLens = LoginPage.lens.buttonState

let newModel1 = titleLens.set(initialState.title)(usernameTextLens.set(initialState.username)(buttonStateLens.set(initialState.buttonState)(oldModel)))

let initialStateLens = Lens.zip(
	titleLens,
	usernameTextLens,
	buttonStateLens)

let newModel2 = initialStateLens
	.set(initialState)(oldModel)

func advanceProcessingMessage(_ previous: String) -> String {
	switch previous {
	case "Please wait":
		return "Almost there"
	case "Almost there":
		return "ALMOST THERE"
	default:
		return previous + "!"
	}
}

let processingPrism = ViewState<Button>.prism.processing

let newModel3 = buttonStateLens.over(processingPrism.tryOver(advanceProcessingMessage))(oldModel)

infix operator •

func • <A,B,C> (
	_ left: @escaping (B) -> C,
	_ right: @escaping (A) -> B)
	-> (A) -> C
{
	return { left(right($0)) }
}

let onProcessing = buttonStateLens.over • processingPrism.tryOver

let newModel4 = onProcessing(advanceProcessingMessage)(oldModel)

struct LensLaw {
	static func setGet<Whole, Part>(
		lens: Lens<Whole,Part>,
		whole: Whole, part: Part)
		-> Bool where Part: Equatable
	{
		return lens.get(lens.set(part)(whole)) == part
	}
}

extension Dictionary {
	static func lens(at key: Key) -> Lens<Dictionary,Value?> {
		return Lens<Dictionary,Value?>(
			get: { $0[key] },
			set: { part in
				{ whole in
					var m_dict = whole
					m_dict[key] = part
					return m_dict
				}
		})
	}
}

//func wrongCompose<A,B,C>(
//	_ first: Lens<A,B?>,
//	_ second: Lens<B,C>)
//	-> Lens<A,C?>

func rightCompose<A,B,C>(
	_ first: Lens<A,B?>,
	_ second: Lens<B,C>,
	injecting: @escaping @autoclosure () -> B)
	-> Lens<A,C?>
{
	return Lens<A,C?>.init(
		get: { whole in first.get(whole).map(second.get) },
		set: { optionalPart in { whole in
			switch optionalPart {
			case .some(let value):
				return first.set(second.set(value)(first.get(whole) ?? injecting()))(whole)
			case .none:
				return first.set(nil)(whole)
			}
		}
	})
}

extension WritableKeyPath {
	var lens: Lens<Root,Value> {
		return Lens<Root,Value>.init(
			get: { whole in whole[keyPath: self] },
			set: { part in
				{ whole in
					var m = whole
					m[keyPath: self] = part
					return m
				}
		})
	}
}

let passwordLens = (\LoginPage.credentials.passwordField.text).lens

"OK"

/*: ### Removed slides

```swift, [.highlight: 2]
extension Dictionary {
static func lens(at key: Key) -> Lens<Dictionary,Value?> {
return Lens<Dictionary,Value?>(
get: { $0[key] },
set: { part in
{ whole in
var m_dict = whole
m_dict[key] = part
return m_dict
}
})
}
}
```

^
part is optional
this is not composable anymore

---

### `Lens<A,B?> + Lens<B,C> = ?`

---

### `Lens<A,B?> + Lens<B,C> = Lens<A,C?>`

---

```swift
func compose<A,B,C>(
_ first: Lens<A,B?>,
_ second: Lens<B,C>)
-> Lens<A,C?> {
/// some code
}
```

^
this is wrong just by the signature
setGet will fail

---

```swift, [.highlight: 4]
func compose<A,B,C>(
_ first: Lens<A,B?>,
_ second: Lens<B,C>,
injecting: B)
-> Lens<A,C?> {
/// some code
}
```

^
I need to produce B
in testing it, I need to produce random Bs to inject to prove that it works

---

*/
