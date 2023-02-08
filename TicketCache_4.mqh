#property copyright "Xefino"
#property version   "1.04"
#property strict

#include <order-send-common-mt4\Primes.mqh>

// Entry
// Describes a single entry in the ticket cache
struct Entry {
public:
   int            HashCode;   // The hash code associated with the entry
   ulong          Key;        // The key for the entry
   ulong          Value;      // The value for the entry
   int            Next;       // The index of the next entry, to use when collisions occur
   
   // Creates a new instance of the Entry with default values
   Entry(): HashCode(0), Key(0), Value(NULL), Next(0) {};
};

// TicketCache
// Describes a hash-map containing mappings between the ticket numbers received from the master
// and local tickets so we can map between them
class TicketCache {
protected:
   int   m_buckets[];   // The buckets to use for handling collisions on the hashmap
   Entry m_entries[];   // The actual data contained in the cache
   int   m_count;       // The number of entries contained in the cache
   int   m_capacity;    // The capacity of the cache
   int   m_free_list;   // The index of the start of the free-list
   int   m_free_count;  // The number of entries that can be added before the cache needs resizing

   // Helper function that initializes the cache with a given capacity
   //    capacity:   The desired capacity of the tickets cache
   void Initialize(const int capacity);
   
   // Helper function that resizes the cache to hold a given number of elements. This
   // function will return true if the operation was successful, or false otherwise
   //    newSize:    The new size of the cache
   bool Resize(int newSize);
   
   // Helper function that gets the index of the key contained in the cache
   //    key:        The key value to search for
   int FindEntry(const ulong key) const;
   
   // Helper function that sets the provided value to the key in the cache. This function will
   // return true if the operation was successful, or false otherwise
   //    key:        The key that should be searched for
   //    value:      The value of the ticket that should be associated with the key
   //    add:        A flag that determines whether or not updates should be allowed. If this flag is
   //                set to true, then only adds will be allowed. If false, updates will be allowed
   bool Insert(const ulong key, ulong value, const bool add);
   
   // The collision threshold to set for all instances of the cache
   static int m_collision_threshold;
   
public:

   // Creates a new instance of the tickets cache with default values
   TicketCache() : m_count(0), m_free_list(0), m_free_count(0), m_capacity(0) { };
   
   // Creates a new instance of the tickets cache with a defined capacity
   //    capacity:   The initial, desired capacity of the tickets cache
   TicketCache(const int capacity);
   
   // Adds a new entry to cache at the key provided. This function will return true
   // if the item was added, or false otherwise
   //    key:        Yhe key to use as an address for the value
   //    value:      The ticket being cached
   bool Add(const ulong key, const ulong value);
   
   // Count returns the number of items in the cache
   int Count() const { return m_count - m_free_count; }
   
   // Contains determines whether or not the key provided points to the value provided,
   // returning true if this was the case and false otherwise.
   //    key:        The key to search for
   //    value:      The ticket that was expected to be associated with the key
   bool Contains(const ulong key, const ulong value) const;
   
   // ContainsKey returns true if the key exists in the cache, false otherwise
   //    key:        The key to search for
   bool ContainsKey(const ulong key) const;
   
   // ContainsValue returns true if the value exists in the cache, false otherwise
   //    value:      The ticket to search for
   bool ContainsValue(const ulong value) const;
   
   // Copies the data in the cache into a list of keys and values, with an optional
   // starting offset. This function will return the number of entries that were copied
   //    dstKeys:    The array that will contain the cache keys
   //    dstValues:  The array that will contain the tickets
   //    dstStart:   The offset from which to start copying data, defaults to 0
   int CopyTo(ulong &dstKeys[], ulong &dstValues[], const int dstStart = 0) const;
   
   // Clear removes all values from the cache
   void Clear();
   
   // Remove deletes the cache entry associated with the key. This function will return
   // true if the item was found and removed, or false otherwise
   //    key:        The key of the object to be deleted
   bool Remove(const ulong key);
   
   // TryGetValue attempts to retrieve the item associated with the key from the cache, returning
   // true if the item was found or false otherwise
   //    key:        The key of the item being searched for
   //    value:      A reference that should hold the value if it is found
   bool TryGetValue(const ulong key, ulong &value) const;
   
   // TrySetValue attempts to set the item associated with the key to value provided, returning
   // true if the item was found or false otherwise
   //    key:        The key of the item being updated
   //    value:      The new value that should be associated with the key
   bool TrySetValue(const ulong key, const ulong value);

   // Values retrieves all the values contained in the cache
   //    values:     A list that should hold all the values in the cache
   void Values(ulong &values[]) const;
};

// Creates a new instance of the tickets cache with a defined capacity
//    capacity:   The initial, desired capacity of the tickets cache
TicketCache::TicketCache(const int capacity) {
   m_count = 0;
   m_free_list = 0;
   m_free_count = 0;
   if (capacity > 0) {
      Initialize(capacity);
   } else {
      m_capacity = 0;
   }
}

// Adds a new entry to cache at the key provided. This function will return true
// if the item was added, or false otherwise
//    key:        Yhe key to use as an address for the value
//    value:      The ticket being cached
bool TicketCache::Add(const ulong key, const ulong value) {
   return Insert(key, value, true);
}

// Contains determines whether or not the key provided points to the value provided,
// returning true if this was the case and false otherwise.
//    key:        The key to search for
//    value:      The ticket that was expected to be associated with the key
bool TicketCache::Contains(const ulong key, const ulong value) const {
   int i = FindEntry(key);
   return i >= 0 && m_entries[i].Value == value;
}

// ContainsKey returns true if the key exists in the cache, false otherwise
//    key:        The key to search for
bool TicketCache::ContainsKey(const ulong key) const {
   return FindEntry(key) >= 0;
}

// ContainsValue returns true if the value exists in the cache, false otherwise
//    value:      The ticket to search for
bool TicketCache::ContainsValue(const ulong value) const {
   for (int i = 0; i < m_count; i++) {
      if (m_entries[i].HashCode >= 0 && m_entries[i].Value == value) {
         return true;
      }
   }
   
   return false;
}

// Copies the data in the cache into a list of keys and values, with an optional
// starting offset. This function will return the number of entries that were copied
//    dstKeys:    The array that will contain the cache keys
//    dstValues:  The array that will contain the tickets
//    dstStart:   The offset from which to start copying data, defaults to 0
int TicketCache::CopyTo(ulong &dstKeys[], ulong &dstValues[], const int dstStart = 0) const {
   
   // First, get the size of the cache and resize the list of keys
   int count = m_count - m_free_count;
   if (dstStart + count > ArraySize(dstKeys)) {
      ArrayResize(dstKeys, dstStart + count);
   }
   
   // Next, resize the list of values if it necessary. It should have the same
   // size as the list of the keys
   if (dstStart + count > ArraySize(dstValues)) {
      ArrayResize(dstValues, MathMin(ArraySize(dstKeys), dstStart + count));
   }
   
   // Now, iterate over all the keys and values and copy them into the destination lists
   int index = 0;
   for (int i = 0; i < ArraySize(m_entries); i++) {
      if(m_entries[i].HashCode >= 0) {
      
         // If we're off the end of the list then return the index here
         if(dstStart + index >= ArraySize(dstKeys) || 
            dstStart + index >= ArraySize(dstValues) || index >= count) {
            return index;
         }
         
         // Otherwise, set the key and value to the associated entry in the cache and
         // update the index
         dstKeys[dstStart + index] = m_entries[i].Key;
         dstValues[dstStart + index] = m_entries[i].Value;
         index++;
      }
   }
        
   // Finally, return the last index of the cache
   return index;
}

// Clear removes all values from the cache
void TicketCache::Clear() {
   if (m_count > 0) {
      ArrayFill(m_buckets, 0, m_capacity, -1);
      ArrayFree(m_entries);
      m_count = 0;
      m_free_list = -1;
      m_free_count = 0;
   }
}

// Remove deletes the cache entry associated with the key. This function will return true if
// the item was found and removed, or false otherwise
//    key:        The key of the object to be deleted
bool TicketCache::Remove(const ulong key) {
   if (m_capacity != 0) {
   
      // Generate the hash key and bucket associated with it
      int hashCode = (int)(key & 0x7FFFFFFF);
      int bucket = hashCode % m_capacity;
      int last = -1;
      
      // Iterate over all the items in the cache until we find the one we're looking for
      for (int i = m_buckets[bucket]; i >= 0; last = i, i = m_entries[i].Next) {
         if (m_entries[i].HashCode == hashCode && m_entries[i].Key == key) {
         
            // First, if last is less than zero (the first entry) the set the value of
            // the bucket to the next value; otherwise, set the value of the next pointer
            // of the previous entry to the next value of the current entry
            if (last < 0) {
               m_buckets[bucket] = m_entries[i].Next;
            } else {
               m_entries[last].Next = m_entries[i].Next;
            }
            
            // Next, update the entry associated with this key
            m_entries[i].HashCode = -1;
            m_entries[i].Next = m_free_list;
            m_entries[i].Key = NULL;
            m_entries[i].Value = NULL;
            
            // Finally, update the number of free entries and index of the last free entry
            // then return true
            m_free_list = i;
            m_free_count++;
            return true;
         }
      }
   }
   
   // We didn't find anything for the key so return false
   return false;
}

// TryGetValue attempts to retrieve the item associated with the key from the cache, returning
// true if the item was found or false otherwise
//    key:        The key of the item being searched for
//    value:      A reference that should hold the value if it is found
bool TicketCache::TryGetValue(const ulong key, ulong &value) const {
   int i = FindEntry(key);
   if (i >= 0) {
      value = m_entries[i].Value;
      return true;
   }
   
   return false;
}

// TrySetValue attempts to set the item associated with the key to value provided, returning
// true if the item was found or false otherwise
//    key:        The key of the item being updated
//    value:      The new value that should be associated with the key
bool TicketCache::TrySetValue(const ulong key, const ulong value) {
   return Insert(key, value, false);
}

// Values retrieves all the values contained in the cache
//    values:     A list that should hold all the values in the cache
void TicketCache::Values(ulong &values[]) const {
   ArrayResize(values, Count());
   int index = 0;
   for (int i = 0; i < ArraySize(m_entries); i++) {
      if (m_entries[i].Value) {
         values[index] = m_entries[i].Value;
         index++;
      }
   }
}

// Helper function that initializes the cache with a given capacity
//    capacity:   The desired capacity of the tickets cache
void TicketCache::Initialize(const int capacity) {
   m_capacity = PrimeGenerator::GetPrime(capacity);
   ArrayResize(m_buckets, m_capacity);
   ArrayFill(m_buckets, 0, m_capacity, -1);
   ArrayResize(m_entries, m_capacity);
   m_free_list = -1;
}

// Helper function that resizes the cache to hold a given number of elements. This
// function will return true if the operation was successful, or false otherwise
//    newSize:    The new size of the cache
bool TicketCache::Resize(const int newSize) {

   // First, attempt to resize the buckets list; if this fails then return false
   if (ArrayResize(m_buckets, newSize) != newSize) {
      return false;
   }
   
   // Next, fill the buckets list with empty values and then attempt to resize the
   // entries list; if this fails the nreturn false
   ArrayFill(m_buckets, 0, newSize, -1);
   if (ArrayResize(m_entries, newSize) != newSize) {
      return false;
   }
   
   // Now, iterate over all the entries in the cache and rehash them so that their
   // hash code is valid with the new cache size
   for (int i = 0; i < m_count; i++) {
      if (m_entries[i].HashCode >= 0) {
         int bucket = m_entries[i].HashCode % newSize;
         m_entries[i].Next = m_buckets[bucket];
         m_buckets[bucket] = i;
      }
   }
   
   // Finally, set the capacity and return true
   m_capacity = newSize;
   return true;
}

// Helper function that gets the index of the key contained in the cache
//    key:        The key value to search for
int TicketCache::FindEntry(const ulong key) const {
   if (m_capacity != NULL) {
      int hashCode = (int)(key & 0x7FFFFFFF);
      for (int i = m_buckets[hashCode % m_capacity]; i >= 0; i = m_entries[i].Next) {
         if (m_entries[i].HashCode == hashCode && m_entries[i].Key == key) {
            return i;
         }   
      }      
   }
   
   return -1;
}

// Helper function that sets the provided value to the key in the cache. This function will
// return true if the operation was successful, or false otherwise
//    key:        The key that should be searched for
//    value:      The value of the ticket that should be associated with the key
//    add:        A flag that determines whether or not updates should be allowed. If this flag is
//                set to true, then only adds will be allowed. If false, updates will be allowed
bool TicketCache::Insert(const ulong key, const ulong value, const bool add) {
   
   // First, check that the capacity isn't zero. If it is, then initialize the cache
   if (m_capacity == 0) {
      Initialize(0);
   }
   
   // Calculate the hash code and target bucket for the key
   int hashCode = (int)(key & 0x7FFFFFFF);
   int targetBucket = hashCode % m_capacity;
   
   // Next, iterate over the buckets until we find one that matches the hash-code we're looking
   // for or we find an entry that hasn't been set
   int collisionCount = 0;
   for (int i = m_buckets[targetBucket]; i >= 0; i = m_entries[i].Next) {
   
      // Check if the hash-code matches; if it doesn't then we have a collision so update our
      // collision count and continue
      if (m_entries[i].HashCode != hashCode) {
         collisionCount++;
         continue;
      }
      
      // If we reached this point then the hash-code matched so check if the key matches
      if (m_entries[i].Key == key) {
      
         // If we only want to allow adds then return false here as we already have an item in the cache
         if (add) {
            return false;
         }
         
         // If we reached this point then updates are allowed so update the value and return true
         m_entries[i].Value = value;
         return true;
      }
   }
   
   // Now, if the collision cound is greater than our collision threshold then resize the cache
   if (collisionCount >= m_collision_threshold) {
   
      // Generate a new prime number to guard against bunching and then attempt a resize. If this
      // fails then the add will fail so return false
      int newSize = PrimeGenerator::ExpandPrime(m_count);
      if (!Resize(newSize)) {
         return false;
      }
      
      // Update the target bucket with the new size
      targetBucket = hashCode % newSize;
   }
   
   // Check if we have free slots left; if we do then update the last index of the free-list and
   // update the free count; otherwise, we'll have to resize the cache
   int index;
   if (m_free_count > 0) {
      index = m_free_list;
      m_free_list = m_entries[index].Next;
      m_free_count--;
   } else {
   
      // If the count is equal to the number of entries then expand the cache here
      if (m_count == ArraySize(m_entries)) {
         int newSize = PrimeGenerator::ExpandPrime(m_count);
         if (!Resize(newSize)) {
            return false;
         }
            
         targetBucket = hashCode % newSize;
      }
      
      // Set the index to the start of the new space and update the count
      index = m_count;
      m_count++;
   }
   
   // Finally, set the entry associated with the entry to the value we're adding and return true
   m_entries[index].HashCode = hashCode;
   m_entries[index].Next = m_buckets[targetBucket];
   m_entries[index].Key = key;
   m_entries[index].Value = value;
   m_buckets[targetBucket] = index;
   return true;
}

// The collision threshold to set for all instances of the cache
static int TicketCache::m_collision_threshold = 8;