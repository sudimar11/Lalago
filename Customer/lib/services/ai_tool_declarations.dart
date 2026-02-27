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
    'Add one or more products to the user\'s cart. Use product IDs from search results.',
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
