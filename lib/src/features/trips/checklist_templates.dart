class ChecklistTemplateEntry {
  final String title;
  final bool isShared;
  final bool isCritical;

  const ChecklistTemplateEntry({
    required this.title,
    this.isShared = false,
    this.isCritical = false,
  });
}

class ChecklistTemplateSection {
  final String title;
  final List<ChecklistTemplateEntry> items;

  const ChecklistTemplateSection({required this.title, required this.items});
}

class ChecklistTemplate {
  final String id;
  final String title;
  final String description;
  final List<ChecklistTemplateSection> sections;

  const ChecklistTemplate({
    required this.id,
    required this.title,
    required this.description,
    required this.sections,
  });
}

const List<ChecklistTemplate> checklistTemplates = [
  ChecklistTemplate(
    id: 'weekend',
    title: 'Weekend / Short Trip',
    description: '2 to 4 days, quick essentials.',
    sections: [
      ChecklistTemplateSection(
        title: 'Essentials',
        items: [
          ChecklistTemplateEntry(title: 'ID / Driver license'),
          ChecklistTemplateEntry(title: 'Phone + charger'),
          ChecklistTemplateEntry(title: 'Wallet'),
          ChecklistTemplateEntry(title: 'Ride / parking plan', isShared: true),
        ],
      ),
      ChecklistTemplateSection(
        title: 'Clothing',
        items: [
          ChecklistTemplateEntry(title: 'Casual outfits (2-3)'),
          ChecklistTemplateEntry(title: 'Sleepwear'),
          ChecklistTemplateEntry(title: 'Underwear and socks'),
        ],
      ),
      ChecklistTemplateSection(
        title: 'Toiletries',
        items: [ChecklistTemplateEntry(title: 'Toiletry kit')],
      ),
      ChecklistTemplateSection(
        title: 'Tech',
        items: [
          ChecklistTemplateEntry(title: 'Power bank'),
          ChecklistTemplateEntry(title: 'Headphones'),
        ],
      ),
      ChecklistTemplateSection(
        title: 'Documents',
        items: [
          ChecklistTemplateEntry(title: 'Hotel confirmation', isShared: true),
        ],
      ),
    ],
  ),
  ChecklistTemplate(
    id: 'domestic-flight',
    title: 'Domestic Flight Trip',
    description: 'Airport essentials + carry-on basics.',
    sections: [
      ChecklistTemplateSection(
        title: 'Airport essentials',
        items: [
          ChecklistTemplateEntry(title: 'Government ID'),
          ChecklistTemplateEntry(title: 'Boarding pass'),
          ChecklistTemplateEntry(title: 'Phone + charger'),
          ChecklistTemplateEntry(title: 'Headphones'),
        ],
      ),
      ChecklistTemplateSection(
        title: 'Carry-on',
        items: [
          ChecklistTemplateEntry(title: 'Snacks'),
          ChecklistTemplateEntry(title: 'Reusable water bottle'),
          ChecklistTemplateEntry(title: 'TSA liquids'),
          ChecklistTemplateEntry(title: 'Medications'),
        ],
      ),
      ChecklistTemplateSection(
        title: 'Checked bag',
        items: [ChecklistTemplateEntry(title: 'Luggage tag')],
      ),
      ChecklistTemplateSection(
        title: 'Before leaving home',
        items: [
          ChecklistTemplateEntry(title: 'Lock doors / turn off appliances'),
          ChecklistTemplateEntry(
            title: 'Ride to airport booked',
            isShared: true,
          ),
        ],
      ),
    ],
  ),
  ChecklistTemplate(
    id: 'international',
    title: 'International Trip',
    description: 'Documents, money, health, and tech.',
    sections: [
      ChecklistTemplateSection(
        title: 'Documents',
        items: [
          ChecklistTemplateEntry(title: 'Passport', isCritical: true),
          ChecklistTemplateEntry(title: 'Visa (if required)', isCritical: true),
          ChecklistTemplateEntry(title: 'Passport copies (digital + physical)'),
        ],
      ),
      ChecklistTemplateSection(
        title: 'Money',
        items: [
          ChecklistTemplateEntry(title: 'Currency / FX card'),
          ChecklistTemplateEntry(title: 'Credit card (no foreign fees)'),
        ],
      ),
      ChecklistTemplateSection(
        title: 'Tech',
        items: [
          ChecklistTemplateEntry(title: 'International SIM / eSIM'),
          ChecklistTemplateEntry(title: 'Power adapter'),
        ],
      ),
      ChecklistTemplateSection(
        title: 'Health',
        items: [
          ChecklistTemplateEntry(title: 'Travel insurance'),
          ChecklistTemplateEntry(title: 'Medications + prescriptions'),
        ],
      ),
      ChecklistTemplateSection(
        title: 'Packing essentials',
        items: [
          ChecklistTemplateEntry(title: 'Emergency contacts', isShared: true),
        ],
      ),
    ],
  ),
  ChecklistTemplate(
    id: 'beach',
    title: 'Beach / Resort Trip',
    description: 'Beachwear, sun protection, and extras.',
    sections: [
      ChecklistTemplateSection(
        title: 'Beachwear',
        items: [
          ChecklistTemplateEntry(title: 'Swimsuits'),
          ChecklistTemplateEntry(title: 'Flip-flops / sandals'),
          ChecklistTemplateEntry(title: 'Beach towel'),
        ],
      ),
      ChecklistTemplateSection(
        title: 'Sun protection',
        items: [
          ChecklistTemplateEntry(title: 'Sunscreen'),
          ChecklistTemplateEntry(title: 'Sunglasses'),
          ChecklistTemplateEntry(title: 'Hat'),
        ],
      ),
      ChecklistTemplateSection(
        title: 'Casual wear',
        items: [ChecklistTemplateEntry(title: 'Casual outfits')],
      ),
      ChecklistTemplateSection(
        title: 'Extras',
        items: [
          ChecklistTemplateEntry(title: 'Evening wear'),
          ChecklistTemplateEntry(title: 'Waterproof phone pouch'),
        ],
      ),
    ],
  ),
  ChecklistTemplate(
    id: 'group',
    title: 'Group Trip (Friends / Family)',
    description: 'Shared responsibilities and coordination.',
    sections: [
      ChecklistTemplateSection(
        title: 'Shared responsibilities',
        items: [
          ChecklistTemplateEntry(title: 'Grocery plan', isShared: true),
          ChecklistTemplateEntry(title: 'Alcohol / drinks', isShared: true),
        ],
      ),
      ChecklistTemplateSection(
        title: 'Travel logistics',
        items: [
          ChecklistTemplateEntry(
            title: 'Airport pickup coordination',
            isShared: true,
          ),
        ],
      ),
      ChecklistTemplateSection(
        title: 'House items',
        items: [
          ChecklistTemplateEntry(title: 'Speaker / music', isShared: true),
          ChecklistTemplateEntry(title: 'Games / cards', isShared: true),
        ],
      ),
      ChecklistTemplateSection(
        title: 'Fun',
        items: [
          ChecklistTemplateEntry(
            title: 'House rules / schedule',
            isShared: true,
          ),
          ChecklistTemplateEntry(
            title: 'Emergency contact shared',
            isShared: true,
          ),
        ],
      ),
    ],
  ),
];
