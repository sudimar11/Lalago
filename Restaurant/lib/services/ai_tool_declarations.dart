import 'package:firebase_ai/firebase_ai.dart';

/// Function declarations for Restaurant Ash tools.
final List<FunctionDeclaration> restaurantAiToolDeclarations = [
  FunctionDeclaration(
    'get_demand_forecast',
    'Get demand forecast for a specific date. Returns hourly order '
    'predictions and product demand.',
    parameters: {
      'date': Schema.string(
        description: 'Date in YYYY-MM-DD format. Use today or tomorrow.',
        nullable: true,
      ),
    },
    optionalParameters: ['date'],
  ),
  FunctionDeclaration(
    'check_inventory',
    'Check current stock levels for products. Returns inventory status '
    'if configured.',
    parameters: {},
  ),
  FunctionDeclaration(
    'view_driver_performance',
    'Get driver performance metrics: acceptance rate, on-time percentage, '
    'ratings, and efficiency scores.',
    parameters: {},
  ),
  FunctionDeclaration(
    'reorder_suggestions',
    'Get purchase quantity recommendations based on demand forecasts.',
    parameters: {
      'productId': Schema.string(
        description: 'Product ID to get suggestion for. Omit for all.',
        nullable: true,
      ),
    },
    optionalParameters: ['productId'],
  ),
  FunctionDeclaration(
    'get_sales_insights',
    'Get sales insights: revenue, popular items, peak hours for '
    'the restaurant.',
    parameters: {
      'period': Schema.string(
        description: 'today, week, or month.',
        nullable: true,
      ),
    },
    optionalParameters: ['period'],
  ),
  FunctionDeclaration(
    'check_restaurant_status',
    'Check if the restaurant is currently open and acceptance settings.',
    parameters: {},
  ),
];
