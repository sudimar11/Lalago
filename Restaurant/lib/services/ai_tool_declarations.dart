import 'package:google_generative_ai/google_generative_ai.dart';

/// Function declarations for Restaurant Ash tools.
List<FunctionDeclaration> get restaurantAiToolDeclarations => [
  FunctionDeclaration(
    'get_demand_forecast',
    'Get demand forecast for a specific date. Returns hourly order predictions '
    'and product demand.',
    Schema.object(
      properties: {
        'date': Schema.string(
          description: 'Date in YYYY-MM-DD format. Use today or tomorrow.',
          nullable: true,
        ),
      },
    ),
  ),
  FunctionDeclaration(
    'check_inventory',
    'Check current stock levels for products. Returns inventory status if '
    'configured.',
    null,
  ),
  FunctionDeclaration(
    'view_driver_performance',
    'Get driver performance metrics: acceptance rate, on-time percentage, '
    'ratings, and efficiency scores.',
    null,
  ),
  FunctionDeclaration(
    'reorder_suggestions',
    'Get purchase quantity recommendations based on demand forecasts.',
    Schema.object(
      properties: {
        'productId': Schema.string(
          description: 'Product ID to get suggestion for. Omit for all.',
          nullable: true,
        ),
      },
    ),
  ),
  FunctionDeclaration(
    'get_sales_insights',
    'Get sales insights: revenue, popular items, peak hours for the restaurant.',
    Schema.object(
      properties: {
        'period': Schema.string(
          description: 'today, week, or month.',
          nullable: true,
        ),
      },
    ),
  ),
  FunctionDeclaration(
    'check_restaurant_status',
    'Check if the restaurant is currently open and acceptance settings.',
    null,
  ),
];
