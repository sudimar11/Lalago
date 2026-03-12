import 'package:firebase_ai/firebase_ai.dart';

/// Function declarations for AI chat tools (Gemini function calling).
final List<FunctionDeclaration> aiToolDeclarations = [
  FunctionDeclaration(
    'get_order_status',
    'Get the current status and estimated delivery time of a food order by order ID.',
    parameters: {
      'orderId': Schema.string(
        description: 'The order ID from the order confirmation.',
      ),
    },
  ),
  FunctionDeclaration(
    'get_active_orders',
    'Get the list of active (in-progress) orders for the current user.',
    parameters: {},
  ),
  FunctionDeclaration(
    'add_products_to_cart',
    'Add one or more products to the user\'s cart. Use product IDs from '
    'search results. Never add items from a closed restaurant.',
    parameters: {
      'items': Schema.array(
        description: 'List of items to add, each with productId and quantity.',
        items: Schema.object(
          properties: {
            'productId': Schema.string(
              description: 'Product ID from vendor_products.',
            ),
            'quantity': Schema.integer(
              description: 'Quantity to add.',
            ),
          },
        ),
      ),
    },
  ),
  FunctionDeclaration(
    'check_restaurant_status',
    'Check if a restaurant is currently open and accepting orders. Returns '
    'open status, today\'s hours, and scheduling availability.',
    parameters: {
      'vendorId': Schema.string(
        description: 'The ID of the restaurant (vendor) to check.',
      ),
    },
  ),
  FunctionDeclaration(
    'apply_best_coupon',
    'Find and apply the best available coupon or offer for the user\'s cart.',
    parameters: {},
  ),
  FunctionDeclaration(
    'get_cart_summary',
    'Get the current cart contents and subtotal.',
    parameters: {},
  ),
  FunctionDeclaration(
    'book_table',
    'Book a table at a restaurant. Requires user confirmation before finalizing.',
    parameters: {
      'vendorId': Schema.string(
        description: 'Restaurant ID from search results.',
      ),
      'date': Schema.string(
        description: 'Date in YYYY-MM-DD format.',
      ),
      'time': Schema.string(
        description: 'Time e.g. 19:00 for 7pm.',
      ),
      'totalGuests': Schema.integer(
        description: 'Number of guests.',
      ),
      'occasion': Schema.string(
        description: 'Optional: birthday, anniversary, etc.',
        nullable: true,
      ),
    },
    optionalParameters: ['occasion'],
  ),
  FunctionDeclaration(
    'report_issue',
    'Submit a report about an order issue (missing items, wrong order, etc.).',
    parameters: {
      'orderId': Schema.string(
        description: 'The order ID to report.',
      ),
      'issueTypes': Schema.array(
        description: 'List of issue types: late_delivery, wrong_items, '
            'missing_items, cold_food, spilled_damaged, driver_issue, '
            'payment_issue, other.',
        items: Schema.string(),
      ),
      'description': Schema.string(
        description: 'Optional additional description.',
        nullable: true,
      ),
    },
    optionalParameters: ['description'],
  ),
  FunctionDeclaration(
    'get_user_membership_info',
    'Get the user\'s referral code, wallet balance, and membership details.',
    parameters: {},
  ),
  FunctionDeclaration(
    'search_products',
    'Search for products (dishes, ingredients) by name or description.',
    parameters: {
      'query': Schema.string(
        description: 'Search query (e.g. carrot cake, pizza, milk tea).',
      ),
    },
  ),
  FunctionDeclaration(
    'search_restaurants',
    'Search for restaurants by name or cuisine.',
    parameters: {
      'query': Schema.string(
        description: 'Search query (e.g. seafood, pizza, Filipino).',
      ),
    },
  ),
  FunctionDeclaration(
    'get_popular_items',
    'Get today\'s most popular food items by order count. '
    'Use when user asks "what\'s popular", "popular today", "trending".',
    parameters: {},
  ),
  FunctionDeclaration(
    'get_popular_items_at_restaurant',
    'Get the most popular food items at a specific restaurant by order count. '
    'Use when user asks "most popular at [restaurant]", "best sellers at '
    '[restaurant]", "what\'s popular at [restaurant]". Pass vendorId if known '
    'from search_restaurants, or restaurantName to look up the restaurant.',
    parameters: {
      'vendorId': Schema.string(
        description: 'Restaurant ID from search_restaurants. Use if known.',
        nullable: true,
      ),
      'restaurantName': Schema.string(
        description: 'Restaurant name (e.g. "Coffee Cat Cafe"). '
            'Used if vendorId not provided.',
        nullable: true,
      ),
      'timeRange': Schema.string(
        description: 'Time range: today, week, month, or all. Default: week.',
        nullable: true,
      ),
      'limit': Schema.integer(
        description: 'Max items to return. Default 10.',
        nullable: true,
      ),
    },
    optionalParameters: ['vendorId', 'restaurantName', 'timeRange', 'limit'],
  ),
  FunctionDeclaration(
    'check_delivery_deadline',
    'Check if an order\'s delivery can meet a specific time deadline.',
    parameters: {
      'orderId': Schema.string(
        description: 'The order ID.',
      ),
      'deadlineTime': Schema.string(
        description: 'Target time e.g. 18:00 for 6pm.',
      ),
    },
  ),
];
