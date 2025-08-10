import Foundation
import CoreML
import AVFoundation
import CoreMedia
import CoreVideo
import Vision

final class YOLOv8Processor {
    private let model: yolov8n_oiv7
    private let classNames: [String]
    private let metalResizer: MetalImageResizer?
    private let processingLock = NSLock()
    private var isProcessing = false
    
    // Base thresholds
    private let baseDefaultThreshold: Float = 0.05
    private let baseSmallObjectThreshold: Float = 0.025
    private let baseUltraSmallThreshold: Float = 0.01
    private let basePersonThreshold: Float = 0.10
    private let iouThreshold: Float = 0.4
    private var targetSide: Int = 640  // can be 352/416/512/640 by tier
    
    // Small objects from Python code
    private let smallObjects = Set([
        "pen", "pencil", "eraser", "marker", "key", "keys", "coin", "button",
        "needle", "pin", "clip", "paperclip", "stapler", "staple", "tape",
        "scissors", "nail", "screw", "bolt", "nut", "washer", "ring", "earring",
        "necklace", "bracelet", "watch", "glasses", "sunglasses", "toothbrush",
        "razor", "comb", "brush", "hairbrush", "nail clipper", "tweezers",
        "spoon", "fork", "knife"
    ])
    
    private let ultraSmallObjects = Set([
        "pen", "pencil", "pencils", "marker", "stick", "twig", "bug", "ant", "spider", "mosquito", "fly", "bee", "beetle"
    ])
    
    // Define unwanted classes that often give false positives or are too generic
    private let excludedClasses = Set([
        "Building",
        "House",
        "Office building",
        "Skyscraper",
        "Tower",
        "Room",
        "Wall",
        "Ceiling",
        "Floor",
        "Indoor",
        "Outdoor",
        "Furniture",
        "Food",
        "Animal",
        "Vehicle",
        "Clothing",
        "Container",
        "Tool",
        "Plant",
        "Invertebrate",
        "Mammal",
        "Insect",
        "Seafood",
        "Sports equipment",
        "Musical instrument",
        "Kitchen appliance",
        "Home appliance",
        "Office supplies",
        "Personal care",
        "Fashion accessory",
        "Tableware",
        "Kitchenware",
        "Medical equipment",
        "Land vehicle",
        "Watercraft",
        "Weapon",
        "Toy",
        "Reptile"
    ])
    
    // Indoor, Outdoor, and Both sets
    private let indoorClasses: Set<String> = [
        "Accordion", "Adhesive tape", "Alarm clock", "Armadillo", "Backpack", "Bagel", "Baked goods", "Balance beam", "Band-aid", "Banjo", "Barrel", "Bathroom accessory", "Bathroom cabinet", "Bathtub", "Beaker", "Bed", "Beer", "Belt", "Bench", "Bicycle helmet", "Bidet", "Billiard table", "Blender", "Book", "Bookcase", "Boot", "Bottle", "Bottle opener", "Bowl", "Bowling equipment", "Box", "Boy", "Brassiere", "Bread", "Briefcase", "Broccoli", "Bust", "Cabinetry", "Cake", "Cake stand", "Calculator", "Camera", "Can opener", "Candle", "Candy", "Cat furniture", "Ceiling fan", "Cello", "Chair", "Cheese", "Chest of drawers", "Chicken", "Ceiling fan", "Chime", "Chisel", "Chopsticks", "Christmas tree", "Clock", "Closet", "Clothing", "Coat", "Cocktail", "Cocktail shaker", "Coconut", "Coffee", "Coffee cup", "Coffee table", "Coffeemaker", "Coin", "Computer keyboard", "Computer monitor", "Computer mouse", "Container", "Convenience store", "Cookie", "Cooking spray", "Corded phone", "Cosmetics", "Couch", "Countertop", "Cream", "Cricket ball", "Crutch", "Cupboard", "Curtain", "Cutting board", "Dagger", "Dairy Product", "Desk", "Dessert", "Diaper", "Dice", "Digital clock", "Dishwasher", "Dog bed", "Doll", "Door", "Door handle", "Doughnut", "Drawer", "Dress", "Drill (Tool)", "Drink", "Drinking straw", "Drum", "Dumbbell", "Earrings", "Egg (Food)", "Envelope", "Eraser", "Face powder", "Facial tissue holder", "Facial care", "Fashion accessory", "Fast food", "Fax", "Fedora", "Filing cabinet", "Fireplace", "Flag", "Flashlight", "Flowerpot", "Flute", "Food", "Food processor", "Football helmet", "Frying pan", "Furniture", "Gas stove", "Girl", "Glasses", "Glove", "Goggles", "Grinder", "Guacamole", "Guitar", "Hair dryer", "Hair spray", "Hamburger", "Hammer", "Hand dryer", "Handbag", "Harmonica", "Harp", "Hat", "Headphones", "Heater", "Home appliance", "Honeycomb", "Horizontal bar", "Hot dog", "Houseplant", "Human arm", "Human beard", "Human body", "Human ear", "Human eye", "Human face", "Human foot", "Human hair", "Human hand", "Human head", "Human leg", "Human mouth", "Human nose", "Humidifier", "Ice cream", "Indoor rower", "Infant bed", "Ipod", "Jacket", "Jacuzzi", "Jeans", "Jug", "Juice", "Kettle", "Kitchen & dining room table", "Kitchen appliance", "Kitchen knife", "Kitchen utensil", "Kitchenware", "Knife", "Ladder", "Ladle", "Lamp", "Lantern", "Laptop", "Lavender (Plant)", "Light bulb", "Light switch", "Lily", "Lipstick", "Loveseat", "Luggage and bags", "Man", "Maracas", "Measuring cup", "Mechanical fan", "Medical equipment", "Microphone", "Microwave oven", "Milk", "Miniskirt", "Mirror", "Mixer", "Mixing bowl", "Mobile phone", "Mouse", "Muffin", "Mug", "Musical instrument", "Musical keyboard", "Nail (Construction)", "Necklace", "Nightstand", "Oboe", "Organ (Musical Instrument)", "Oven", "Paper cutter", "Paper towel", "Pastry", "Pen", "Pencil case", "Pencil sharpener", "Perfume", "Personal care", "Piano", "Picnic basket", "Picture frame", "Pillow", "Pizza cutter", "Plastic bag", "Plate", "Platter", "Plumbing fixture", "Popcorn", "Porch", "Poster", "Power plugs and sockets", "Pressure cooker", "Pretzel", "Printer", "Punching bag", "Racket", "Refrigerator", "Remote control", "Ring binder", "Rose", "Ruler", "Salad", "Salt and pepper shakers", "Sandal", "Sandwich", "Saucer", "Saxophone", "Scale", "Scarf", "Scissors", "Screwdriver", "Sculpture", "Serving tray", "Sewing machine", "Shelf", "Shirt", "Shorts", "Shower", "Sink", "Skirt", "Slow cooker", "Soap dispenser", "Sock", "Sofa bed", "Sombrero", "Spatula", "Spice rack", "Spoon", "Stairs", "Stapler", "Stationary bicycle", "Stethoscope", "Stool", "Studio couch", "Suit", "Suitcase", "Sun hat", "Sunglasses", "Swim cap", "Swimwear", "Table", "Table tennis racket", "Tablet computer", "Tableware", "Tap", "Tea", "Teapot", "Teddy bear", "Telephone", "Television", "Tennis racket", "Tiara", "Tie", "Tin can", "Toaster", "Toilet", "Toilet paper", "Tool", "Toothbrush", "Torch", "Towel", "Toy", "Training bench", "Treadmill", "Tripod", "Trombone", "Trousers", "Trumpet", "Umbrella", "Vase", "Watch", "Whisk", "Whiteboard", "Willow", "Window", "Window blind", "Wine", "Wine glass", "Wine rack", "Wok", "Woman", "Wood-burning stove", "Wrench", "Apple", "Artichoke", "Banana", "Bell pepper", "Cabbage", "Cantaloupe", "Carrot", "Common fig", "Cucumber", "Garden Asparagus", "Grape", "Grapefruit", "Lemon", "Mango", "Orange", "Peach", "Pear", "Pineapple", "Pomegranate", "Potato", "Pumpkin", "Radish", "Strawberry", "Tomato", "Vegetable", "Watermelon", "Winter melon", "Zucchini"
    ]
    
    private let outdoorClasses: Set<String> = [
        "Aircraft", "Airplane", "Alpaca", "Ambulance", "Animal", "Ant", "Antelope", "Auto part", "Axe", "Ball", "Balloon", "Barge", "Baseball bat", "Baseball glove", "Bat (Animal)", "Bear", "Bee", "Beehive", "Beetle", "Bicycle", "Bicycle wheel", "Billboard", "Binoculars", "Bird", "Blue jay", "Boat", "Bomb", "Bow and arrow", "Brown bear", "Building", "Bull", "Bus", "Butterfly", "Camel", "Cannon", "Canoe", "Car", "Carnivore", "Cart", "Castle", "Caterpillar", "Cattle", "Centipede", "Cheetah", "Crab", "Crocodile", "Crow", "Crown", "Deer", "Dinosaur", "Dog", "Dolphin", "Dragonfly", "Duck", "Eagle", "Falcon", "Fish", "Flower", "Flying disc", "Football", "Fountain", "Fox", "Frog", "Giraffe", "Goat", "Goldfish", "Golf ball", "Golf cart", "Gondola", "Goose", "Hedgehog", "Helicopter", "Hippopotamus", "Horse", "Jaguar (Animal)", "Jellyfish", "Jet ski", "Kangaroo", "Kite", "Koala", "Ladybug", "Land vehicle", "Leopard", "Lighthouse", "Limousine", "Lion", "Lizard", "Lobster", "Lynx", "Mammal", "Marine invertebrates", "Marine mammal", "Missile", "Monkey", "Moths and butterflies", "Motorcycle", "Mule", "Mushroom", "Ostrich", "Otter", "Owl", "Oyster", "Paddle", "Palm tree", "Panda", "Parachute", "Parking meter", "Parrot", "Penguin", "Person", "Pig", "Porcupine", "Rabbit", "Raccoon", "Raven", "Rays and skates", "Red panda", "Reptile", "Rhinoceros", "Rocket", "Roller skates", "Rugby ball", "Ruler", "Salad", "Salt and pepper shakers", "Sandal", "Sandwich", "Saucer", "Saxophone", "Scale", "Scarf", "Scissors", "Scoreboard", "Scorpion", "Screwdriver", "Sculpture", "Sea lion", "Sea turtle", "Seafood", "Seahorse", "Seat belt", "Segway", "Serving tray", "Sewing machine", "Shark", "Sheep", "Shelf", "Shellfish", "Shirt", "Shorts", "Shotgun", "Shower", "Shrimp", "Sink", "Skateboard", "Ski", "Skirt", "Skull", "Skunk", "Slow cooker", "Snack", "Snail", "Snake", "Snowboard", "Snowman", "Snowmobile", "Snowplow", "Sparrow", "Spatula", "Spice rack", "Spider", "Spoon", "Sports equipment", "Sports uniform", "Squash (Plant)", "Squid", "Squirrel", "Starfish", "Stationary bicycle", "Stethoscope", "Stool", "Stop sign", "Strawberry", "Street light", "Stretcher", "Studio couch", "Submarine", "Submarine sandwich", "Suit", "Suitcase", "Sun hat", "Sunglasses", "Surfboard", "Sushi", "Swan", "Swim cap", "Swimming pool", "Swimwear", "Sword", "Syringe", "Table", "Table tennis racket", "Tablet computer", "Tableware", "Taco", "Tank", "Tap", "Tart", "Taxi", "Tea", "Teapot", "Teddy bear", "Telephone", "Television", "Tennis ball", "Tennis racket", "Tent", "Tiara", "Tick", "Tie", "Tiger", "Tin can", "Tire", "Toaster", "Toilet", "Toilet paper", "Tomato", "Tool", "Toothbrush", "Torch", "Tortoise", "Towel", "Tower", "Toy", "Traffic light", "Traffic sign", "Train", "Training bench", "Treadmill", "Tree", "Tree house", "Tripod", "Trombone", "Trousers", "Truck", "Trumpet", "Turkey", "Turtle", "Umbrella", "Unicycle", "Van", "Vase", "Vegetable", "Vehicle", "Vehicle registration plate", "Violin", "Volleyball (Ball)", "Waffle", "Waffle iron", "Wall clock", "Wardrobe", "Washing machine", "Waste container", "Watch", "Watercraft", "Watermelon", "Weapon", "Whale", "Wheel", "Wheelchair", "Whisk", "Whiteboard", "Willow", "Window", "Window blind", "Wine", "Wine glass", "Wine rack", "Winter melon", "Wok", "Woman", "Wood-burning stove", "Woodpecker", "Worm", "Wrench", "Zebra"
    ]
    
    private let bothClasses: Set<String> = [
        "Beer", "Bell pepper", "Blue jay", "Book", "Bottle", "Bowl", "Boy", "Bread", "Broccoli", "Butterfly", "Cabbage", "Cantaloupe", "Carrot", "Cat", "Christmas tree", "Clothing", "Coat", "Cocktail", "Coconut", "Coffee", "Coin", "Common fig", "Common sunflower", "Computer mouse", "Cookie", "Cream", "Crocodile", "Croissant", "Cucumber", "Cupboard", "Curtain", "Cutting board", "Deer", "Dessert", "Digital clock", "Dog", "Door", "Drink", "Drum", "Duck", "Earrings", "Egg (Food)", "Elephant", "Envelope", "Eraser", "Face powder", "Fashion accessory", "Fast food", "Flag", "Flashlight", "Flower", "Flute", "Food", "Football", "Footwear", "Fork", "French fries", "French horn", "Frog", "Fruit", "Frying pan", "Garden Asparagus", "Giraffe", "Girl", "Glasses", "Glove", "Goggles", "Goat", "Grape", "Grapefruit", "Guacamole", "Guitar", "Hair dryer", "Hair spray", "Hamburger", "Hammer", "Hamster", "Hand dryer", "Handbag", "Hat", "Headphones", "Heater", "Honeycomb", "Horse", "Hot dog", "Human arm", "Human beard", "Human body", "Human ear", "Human eye", "Human face", "Human foot", "Human hair", "Human hand", "Human head", "Human leg", "Human mouth", "Human nose", "Ice cream", "Insect", "Invertebrate", "Jacket", "Jeans", "Juice", "Kangaroo", "Kitchen utensil", "Kite", "Knife", "Koala", "Ladybug", "Lemon", "Leopard", "Lily", "Lion", "Lizard", "Lobster", "Lynx", "Magpie", "Mammal", "Man", "Maple", "Maracas", "Measuring cup", "Mechanical fan", "Microphone", "Milk", "Miniskirt", "Mirror", "Mixer", "Mixing bowl", "Mobile phone", "Monkey", "Moths and butterflies", "Mouse", "Muffin", "Mug", "Mule", "Mushroom", "Musical instrument", "Musical keyboard", "Nail (Construction)", "Necklace", "Nightstand", "Oboe", "Office supplies", "Orange", "Organ (Musical Instrument)", "Ostrich", "Otter", "Owl", "Oyster", "Paddle", "Palm tree", "Pancake", "Panda", "Paper cutter", "Paper towel", "Parrot", "Pasta", "Pastry", "Peach", "Pear", "Pen", "Pencil case", "Pencil sharpener", "Penguin", "Perfume", "Person", "Personal care", "Personal flotation device", "Piano", "Picnic basket", "Picture frame", "Pig", "Pillow", "Pineapple", "Pitcher (Container)", "Pizza", "Plant", "Plastic bag", "Plate", "Platter", "Plumbing fixture", "Polar bear", "Pomegranate", "Popcorn", "Porch", "Porcupine", "Poster", "Potato", "Power plugs and sockets", "Pressure cooker", "Pretzel", "Printer", "Pumpkin", "Punching bag", "Rabbit", "Raccoon", "Racket", "Radish", "Ratchet (Device)", "Raven", "Rays and skates", "Red panda", "Refrigerator", "Remote control", "Reptile", "Rhinoceros", "Rifle", "Ring binder", "Rocket", "Roller skates", "Rose", "Rugby ball", "Ruler", "Salad", "Salt and pepper shakers", "Sandal", "Sandwich", "Saucer", "Saxophone", "Scale", "Scarf", "Scissors", "Scoreboard", "Scorpion", "Screwdriver", "Sculpture", "Sea lion", "Sea turtle", "Seafood", "Seahorse", "Seat belt", "Segway", "Serving tray", "Sewing machine", "Shark", "Sheep", "Shelf", "Shellfish", "Shirt", "Shorts", "Shotgun", "Shower", "Shrimp", "Sink", "Skateboard", "Ski", "Skirt", "Skull", "Skunk", "Slow cooker", "Snack", "Snail", "Snake", "Snowboard", "Snowman", "Snowmobile", "Snowplow", "Sparrow", "Spatula", "Spice rack", "Spider", "Spoon", "Sports equipment", "Sports uniform", "Squash (Plant)", "Squid", "Squirrel", "Starfish", "Stationary bicycle", "Stethoscope", "Stool", "Stop sign", "Strawberry", "Street light", "Stretcher", "Studio couch", "Submarine", "Submarine sandwich", "Suit", "Suitcase", "Sun hat", "Sunglasses", "Surfboard", "Sushi", "Swan", "Swim cap", "Swimming pool", "Swimwear", "Sword", "Syringe", "Table", "Table tennis racket", "Tablet computer", "Tableware", "Taco", "Tank", "Tap", "Tart", "Taxi", "Tea", "Teapot", "Teddy bear", "Telephone", "Television", "Tennis ball", "Tennis racket", "Tent", "Tiara", "Tick", "Tie", "Tiger", "Tin can", "Tire", "Toaster", "Toilet", "Toilet paper", "Tomato", "Tool", "Toothbrush", "Torch", "Tortoise", "Towel", "Tower", "Toy", "Traffic light", "Traffic sign", "Train", "Training bench", "Treadmill", "Tree", "Tree house", "Tripod", "Trombone", "Trousers", "Truck", "Trumpet", "Turkey", "Turtle", "Umbrella", "Unicycle", "Van", "Vase", "Vegetable", "Vehicle", "Vehicle registration plate", "Violin", "Volleyball (Ball)", "Waffle", "Waffle iron", "Wall clock", "Wardrobe", "Washing machine", "Waste container", "Watch", "Watercraft", "Watermelon", "Weapon", "Whale", "Wheel", "Wheelchair", "Whisk", "Whiteboard", "Willow", "Window", "Window blind", "Wine", "Wine glass", "Wine rack", "Winter melon", "Wok", "Woman", "Wood-burning stove", "Woodpecker", "Worm", "Wrench", "Zebra", "Zucchini"
    ]
    
    init(targetSide: Int = 640) throws {
        _ = Date()
        
        self.targetSide = targetSide
        
        self.metalResizer = MetalImageResizer()
        
        let config = MLModelConfiguration()
        if #available(iOS 16.0, *) {
            config.computeUnits = .cpuAndNeuralEngine
        } else {
            // iOS 15 fallback - use all available units
            config.computeUnits = .all
        }
        
        _ = Date()
        self.model = try yolov8n_oiv7(configuration: config)

        if let dummy = YOLOv8Processor.createDummyPixelBuffer() {
            _ = Date()
            _ = try? model.prediction(image: dummy)
        }

        self.classNames = Self.loadClassNames() ?? Self.generateDefaultClassNames()
        
        _ = Date()
    }
    
    func configureTargetSide(_ side: Int) {
        self.targetSide = max(320, min(side, 640))
    }
    
    func predict(image: CVPixelBuffer, isPortrait: Bool, filterMode: String = "all", confidenceThreshold: Float = 1.0, completion: @escaping ([YOLODetection]) -> Void) {
        
        processingLock.lock()
        if isProcessing {
            processingLock.unlock()
            completion([])
            return
        }
        isProcessing = true
        processingLock.unlock()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            autoreleasepool {
                defer {
                    self?.processingLock.lock()
                    self?.isProcessing = false
                    self?.processingLock.unlock()
                }
                
                guard let self = self else {
                    DispatchQueue.main.async { completion([]) }
                    return
                }
                // Reset cached state at start of predict to avoid initial mismatches
                UserDefaults.standard.removeObject(forKey: "letterbox_scale")
                UserDefaults.standard.removeObject(forKey: "letterbox_padX")
                UserDefaults.standard.removeObject(forKey: "letterbox_padY")
                UserDefaults.standard.removeObject(forKey: "original_width")
                UserDefaults.standard.removeObject(forKey: "original_height")
                UserDefaults.standard.removeObject(forKey: "was_rotated")

                let imageWidth = CVPixelBufferGetWidth(image)
                let imageHeight = CVPixelBufferGetHeight(image)

                guard imageWidth > 100 && imageHeight > 100 else {
                    DispatchQueue.main.async {
                        completion([])
                    }
                    return
                }

                // Resize to targetSide x targetSide
                let resizedPixelBuffer = self.metalResizer?.resize(image, isPortrait: isPortrait)

                guard let finalBuffer = resizedPixelBuffer else {
                    DispatchQueue.main.async {
                        completion([])
                    }
                    return
                }

                // Read letterbox parameters from UserDefaults
                let scale = UserDefaults.standard.float(forKey: "letterbox_scale")
                let padX = UserDefaults.standard.integer(forKey: "letterbox_padX")
                let padY = UserDefaults.standard.integer(forKey: "letterbox_padY")
                let originalWidth = UserDefaults.standard.integer(forKey: "original_width")
                let originalHeight = UserDefaults.standard.integer(forKey: "original_height")

                // Use the stored values, with fallback to calculated values
                let letterboxInfo: (scale: Float, padX: Int, padY: Int)
                if scale > 0 && originalWidth > 0 && originalHeight > 0 {
                    letterboxInfo = (scale: scale, padX: padX, padY: padY)
                } else {
                    letterboxInfo = self.calculateLetterboxParams(width: imageWidth, height: imageHeight)
                }

                guard let output = try? self.model.prediction(image: finalBuffer) else {
                    DispatchQueue.main.async {
                        completion([])
                    }
                    return
                }

                guard let feature = output.featureValue(for: "var_914"),
                      let rawOutput = feature.multiArrayValue else {
                    DispatchQueue.main.async {
                        completion([])
                    }
                    return
                }

                let detections = self.decodeOutput(rawOutput,
                                                  originalWidth: originalWidth > 0 ? originalWidth : imageWidth,
                                                  originalHeight: originalHeight > 0 ? originalHeight : imageHeight,
                                                  letterboxInfo: letterboxInfo,
                                                  filterMode: filterMode,
                                                  confidenceThreshold: confidenceThreshold)
                DispatchQueue.main.async {
                    completion(detections)
                }
            }
        }
    }
    
    private func calculateLetterboxParams(width: Int, height: Int) -> (scale: Float, padX: Int, padY: Int) {
        let targetSize: Float = Float(self.targetSide)
        let scale = min(targetSize / Float(width), targetSize / Float(height))
        
        let scaledWidth = Int(Float(width) * scale)
        let scaledHeight = Int(Float(height) * scale)
        
        let padX = (self.targetSide - scaledWidth) / 2
        let padY = (self.targetSide - scaledHeight) / 2
        
        return (scale: scale, padX: padX, padY: padY)
    }
    
    private func decodeOutput(_ rawOutput: MLMultiArray,
                            originalWidth: Int,
                            originalHeight: Int,
                            letterboxInfo: (scale: Float, padX: Int, padY: Int),
                            filterMode: String,
                            confidenceThreshold: Float) -> [YOLODetection] {
        let numAnchors = 8400
        let numClasses = 601
        var detections: [YOLODetection] = []
        
        let dataPointer = rawOutput.dataPointer.assumingMemoryBound(to: Float.self)
        let (scale, padX, padY) = letterboxInfo
        
        // Check if the image was rotated during preprocessing
        let wasRotated = UserDefaults.standard.bool(forKey: "was_rotated")
        
        for i in 0..<numAnchors {
            let x_center = dataPointer[i]
            let y_center = dataPointer[numAnchors + i]
            let box_width = dataPointer[2 * numAnchors + i]
            let box_height = dataPointer[3 * numAnchors + i]
            
            // Find best class
            var maxScore: Float = 0
            var bestClass = 0
            
            for c in 0..<numClasses {
                let score = dataPointer[(4 + c) * numAnchors + i]
                if score > maxScore {
                    maxScore = score
                    bestClass = c
                }
            }
            
            let className = bestClass < classNames.count ? classNames[bestClass] : "Unknown"
            
            // Calculate dynamic threshold based on object type and confidence multiplier
            let classLower = className.lowercased()
            let baseThreshold: Float
            if ultraSmallObjects.contains(classLower) {
                baseThreshold = baseUltraSmallThreshold
            } else if smallObjects.contains(classLower) {
                baseThreshold = baseSmallObjectThreshold
            } else if classLower == "person" {
                baseThreshold = basePersonThreshold
            } else {
                baseThreshold = baseDefaultThreshold
            }
            
            let threshold = baseThreshold * confidenceThreshold
            
            guard maxScore > threshold else { continue }
            
            // Filter based on mode
            let allowedClasses: Set<String>
            switch filterMode.lowercased() {
            case "indoor":
                allowedClasses = indoorClasses.union(bothClasses)
            case "outdoor":
                allowedClasses = outdoorClasses.union(bothClasses)
            default:
                allowedClasses = Set(classNames)
            }
            guard allowedClasses.contains(className) else { continue }
            
            // Skip if in padding area
            if x_center < Float(padX) || x_center > Float(self.targetSide - padX) ||
               y_center < Float(padY) || y_center > Float(self.targetSide - padY) {
                continue
            }
            
            // Transform coordinates back to original image space
            let unpadded_x = x_center - Float(padX)
            let unpadded_y = y_center - Float(padY)
            
            let orig_center_x = unpadded_x / scale
            let orig_center_y = unpadded_y / scale
            let orig_w = box_width / scale
            let orig_h = box_height / scale
            
            let orig_x = orig_center_x - orig_w/2
            let orig_y = orig_center_y - orig_h/2
            
            // Normalize to [0,1] considering rotation
            let norm_x: Float
            let norm_y: Float
            let norm_w: Float
            let norm_h: Float
            
            if wasRotated {
                // If the image was rotated 90° clockwise during preprocessing,
                // we need to rotate the coordinates back counter-clockwise
                // When rotated: new dimensions are swapped (height becomes width)
                norm_x = 1.0 - (orig_y / Float(originalHeight))
                norm_y = orig_x / Float(originalWidth)
                norm_w = orig_h / Float(originalHeight)
                norm_h = orig_w / Float(originalWidth)
            } else {
                // Normal case - no rotation
                norm_x = orig_x / Float(originalWidth)
                norm_y = orig_y / Float(originalHeight)
                norm_w = orig_w / Float(originalWidth)
                norm_h = orig_h / Float(originalHeight)
            }
            
            // Validate bounds with tolerance
            guard norm_x >= -0.1, norm_y >= -0.1,
                  norm_x + norm_w <= 1.1, norm_y + norm_h <= 1.1,
                  norm_w > 0.01, norm_h > 0.01 else {
                continue
            }
            
            // Clamp to valid range
            let final_x = max(0, min(1, norm_x))
            let final_y = max(0, min(1, norm_y))
            let final_w = max(0, min(1 - final_x, norm_w))
            let final_h = max(0, min(1 - final_y, norm_h))
            
            let rect = CGRect(x: CGFloat(final_x), y: CGFloat(final_y),
                            width: CGFloat(final_w), height: CGFloat(final_h))
            
            // Skip if detection takes up more than 70% of the screen
            let detectionArea = final_w * final_h
            if detectionArea > 0.7 {
                continue  // Skip large detections
            }

            // Also skip very small detections (less than 0.5% of screen)
            if detectionArea < 0.005 {
                continue
            }

            // Skip if detection width OR height is more than 70% of screen
            // This catches tall/wide objects that might not have large area
            if final_w > 0.7 || final_h > 0.7 {
                continue
            }
            
            detections.append(YOLODetection(
                classIndex: bestClass,
                className: className,
                score: maxScore,
                rect: rect
            ))
        }
        
        // Apply NMS
        let filtered = applyNMS(detections)
        
        // Keep only the highest-confidence detection per class
        var bestDetections: [String: YOLODetection] = [:]
        for detection in filtered {
            if let existing = bestDetections[detection.className] {
                if detection.score > existing.score {
                    bestDetections[detection.className] = detection
                }
            } else {
                bestDetections[detection.className] = detection
            }
        }
        
        return Array(bestDetections.values)
    }
    
    private func applyNMS(_ detections: [YOLODetection]) -> [YOLODetection] {
        let sorted = detections.sorted { $0.score > $1.score }
        var keep: [YOLODetection] = []
        
        for detection in sorted {
            var shouldKeep = true
            
            for kept in keep {
                if kept.className == detection.className {
                    let iou = calculateIoU(rect1: kept.rect, rect2: detection.rect)
                    if iou > iouThreshold {
                        shouldKeep = false
                        break
                    }
                }
            }
            
            if shouldKeep {
                keep.append(detection)
            }
        }
        
        return keep
    }
    
    private func calculateIoU(rect1: CGRect, rect2: CGRect) -> Float {
        let intersection = rect1.intersection(rect2)
        guard !intersection.isNull else { return 0 }
        
        let intersectionArea = intersection.width * intersection.height
        let union = rect1.width * rect1.height + rect2.width * rect2.height - intersectionArea
        
        return Float(intersectionArea / union)
    }

    private static func loadClassNames() -> [String]? {
        for name in ["class_names", "classes", "labels"] {
            if let path = Bundle.main.path(forResource: name, ofType: "txt") {
                return try? String(contentsOfFile: path, encoding: .utf8)
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        }
        return nil
    }

    private static func generateDefaultClassNames() -> [String] {
        return (0..<601).map { "Class_\($0)" }
    }

    private static func createDummyPixelBuffer() -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 640, 640, kCVPixelFormatType_32BGRA, nil, &pb)
        return pb
    }
}
