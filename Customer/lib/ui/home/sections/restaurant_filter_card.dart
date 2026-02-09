import 'package:flutter/material.dart';
import 'package:foodie_customer/constants.dart';
import 'package:foodie_customer/services/helper.dart';

enum SortOption { distance, rating, open, closed, none }

class RestaurantFilterCard extends StatelessWidget {
  final SortOption sortBy;
  final bool filterRating4Plus;
  final bool filterHalal;
  final Function(SortOption) onSortChanged;
  final Function(bool) onRating4PlusChanged;
  final Function(bool) onHalalChanged;
  final VoidCallback onReset;

  const RestaurantFilterCard({
    Key? key,
    required this.sortBy,
    required this.filterRating4Plus,
    required this.filterHalal,
    required this.onSortChanged,
    required this.onRating4PlusChanged,
    required this.onHalalChanged,
    required this.onReset,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool hasActiveFilters =
        sortBy != SortOption.none || filterRating4Plus || filterHalal;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color(COLOR_PRIMARY),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Color(COLOR_PRIMARY),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Color(COLOR_PRIMARY).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Sort Button
          Expanded(
            child: _FilterButton(
              label: sortBy == SortOption.none
                  ? "Sort"
                  : (sortBy == SortOption.distance
                      ? "Distance"
                      : sortBy == SortOption.rating
                          ? "Rating"
                          : sortBy == SortOption.open
                              ? "Open"
                              : "Closed"),
              icon: Icons.sort,
              isActive: sortBy != SortOption.none,
              onTap: () => _showSortBottomSheet(context),
            ),
          ),
          const SizedBox(width: 8),

          // Rating 4+ Button
          Expanded(
            child: _FilterButton(
              label: "Rating 4+",
              icon: Icons.star,
              isActive: filterRating4Plus,
              onTap: () => onRating4PlusChanged(!filterRating4Plus),
            ),
          ),
          const SizedBox(width: 8),

          // Halal Button
          Expanded(
            child: _FilterButton(
              label: "None Halal",
              icon: Icons.restaurant_menu,
              isActive: filterHalal,
              onTap: () => onHalalChanged(!filterHalal),
            ),
          ),

          // Reset Button (only show when filters are active)
          if (hasActiveFilters) ...[
            const SizedBox(width: 8),
            IconButton(
              onPressed: onReset,
              icon: Icon(
                Icons.refresh,
                color: Colors.white,
                size: 20,
              ),
              tooltip: "Reset",
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showSortBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: BoxDecoration(
            color: isDarkMode(context)
                ? const Color(DarkContainerColor)
                : Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Title
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  "Sort By",
                  style: TextStyle(
                    fontFamily: "Poppinssb",
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode(context) ? Colors.white : Colors.black,
                  ),
                ),
              ),

              const Divider(height: 1),

              // Sort Options
              _SortOption(
                title: "Distance",
                subtitle: "Nearest first",
                icon: Icons.location_on,
                isSelected: sortBy == SortOption.distance,
                onTap: () {
                  onSortChanged(SortOption.distance);
                  Navigator.pop(context);
                },
              ),

              _SortOption(
                title: "Rating",
                subtitle: "Highest rated first",
                icon: Icons.star,
                isSelected: sortBy == SortOption.rating,
                onTap: () {
                  onSortChanged(SortOption.rating);
                  Navigator.pop(context);
                },
              ),

              _SortOption(
                title: "Open",
                subtitle: "Open restaurants first",
                icon: Icons.check_circle,
                isSelected: sortBy == SortOption.open,
                onTap: () {
                  onSortChanged(SortOption.open);
                  Navigator.pop(context);
                },
              ),

              _SortOption(
                title: "Closed",
                subtitle: "Closed restaurants first",
                icon: Icons.cancel,
                isSelected: sortBy == SortOption.closed,
                onTap: () {
                  onSortChanged(SortOption.closed);
                  Navigator.pop(context);
                },
              ),

              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}

class _FilterButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _FilterButton({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.white.withOpacity(0.8),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? Colors.white : Colors.white.withOpacity(0.5),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isActive ? Color(COLOR_PRIMARY) : Colors.grey.shade700,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: isActive ? "Poppinssb" : "Poppinsm",
                  fontSize: 12,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: isActive ? Color(COLOR_PRIMARY) : Colors.grey.shade700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _SortOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected
                    ? Color(COLOR_PRIMARY).withOpacity(0.1)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: isSelected ? Color(COLOR_PRIMARY) : Colors.grey.shade600,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: "Poppinssb",
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode(context) ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: "Poppinsr",
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: Color(COLOR_PRIMARY),
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}
